const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// Helper to check if caller is admin or super_admin
async function checkAdmin(request) {
  if (!request.auth) {
    logger.error("[checkAdmin] Request rejected: unauthenticated caller.");
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }
  const tokenRole = (request.auth.token ? (request.auth.token.role || "") : "").toLowerCase();
  logger.info("[checkAdmin] Verifying caller token claims...", { callerUid: request.auth.uid, tokenRole });

  if (tokenRole === "admin") {
    logger.info("[checkAdmin] Caller authorized via token claims.");
    return;
  }

  // Fallback: check user profile document in Firestore
  const callerUid = request.auth.uid;
  try {
    const userDoc = await db.collection("users").doc(callerUid).get();
    if (userDoc.exists) {
      const data = userDoc.data() || {};
      const role = (data.role || "").toLowerCase();
      const username = (data.username || "").toUpperCase();
      logger.info("[checkAdmin] Verifying caller Firestore profile...", { callerUid, role, username });
      if (role === "admin" || username === "MASTER" || username === "IT") {
        logger.info("[checkAdmin] Caller authorized via Firestore profile document.");
        return;
      }
    }
  } catch (err) {
    logger.error("[checkAdmin] Error reading caller document from Firestore:", err);
  }

  logger.error("[checkAdmin] Caller authorization failed: insufficient permissions.", { callerUid });
  throw new HttpsError("permission-denied", "Only admins can perform this action.");
}

// 1. resolveUsernameToEmail
// Allows unauthenticated clients to resolve a username to the hidden email
exports.resolveUsernameToEmail = onCall(async (request) => {
  const { username } = request.data;
  if (!username) {
    throw new HttpsError("invalid-argument", "Username is required");
  }

  try {
    // Query the users collection for the username
    const usersRef = db.collection("users");
    const snapshot = await usersRef.where("username", "==", username.toUpperCase()).limit(1).get();

    if (snapshot.empty) {
      throw new HttpsError("not-found", "User not found");
    }

    const userDoc = snapshot.docs[0].data();
    // Reconstruct the internal email based on our pattern
    const internalEmail = `${username.toLowerCase()}@internal.shifa.app`;
    
    return { email: internalEmail };
  } catch (error) {
    logger.error("Error resolving username", error);
    throw new HttpsError("internal", "An error occurred");
  }
});

// 2. createStaffAccount (Admin Only)
exports.createStaffAccount = onCall(async (request) => {
  await checkAdmin(request);

  const { name, phone } = request.data;
  if (!name || !phone) {
    throw new HttpsError("invalid-argument", "Name and phone are required");
  }

  try {
    // Generate username (e.g. STAFF0001)
    // We can use a counter in firestore, but for simplicity we'll use a random or timestamp based one if needed.
    // For this implementation, let's use a random 4 digit suffix
    const suffix = Math.floor(1000 + Math.random() * 9000);
    const username = `STAFF${suffix}`;
    const internalEmail = `${username.toLowerCase()}@internal.shifa.app`;
    const password = Math.random().toString(36).slice(-8); // Random 8 char password

    // Create Firebase Auth user
    const userRecord = await admin.auth().createUser({
      email: internalEmail,
      password: password,
      displayName: name,
    });

    // Set Custom Claims
    await admin.auth().setCustomUserClaims(userRecord.uid, {
      role: "staff",
      organizationId: "default"
    });

    // Create Firestore Document
    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.collection("users").doc(userRecord.uid).set({
      uid: userRecord.uid,
      username: username,
      name: name,
      phone: phone,
      role: "staff", // For display only
      status: "active",
      organizationId: "default",
      createdBy: request.auth.uid,
      createdAt: now,
      isDeleted: false
    });

    // Log Activity
    await db.collection("activities").add({
      userId: request.auth.uid,
      userName: request.auth.token ? (request.auth.token.name || "Admin") : "Admin",
      role: "admin",
      action: "STAFF_CREATED",
      entityType: "user",
      entityId: userRecord.uid,
      description: `Created staff account for ${name} (${username})`,
      organizationId: "default",
      timestamp: now
    });

    return { 
      uid: userRecord.uid, 
      username: username, 
      password: password 
    };

  } catch (error) {
    logger.error("Error creating staff account", error);
    throw new HttpsError("internal", error.message);
  }
});

// 3. updateUserStatus (Admin Only)
exports.updateUserStatus = onCall(async (request) => {
  await checkAdmin(request);

  const { targetUid, newStatus } = request.data;
  if (!targetUid || !newStatus) {
    throw new HttpsError("invalid-argument", "Missing required parameters");
  }

  const validStatuses = ["active", "disabled", "suspended"];
  if (!validStatuses.includes(newStatus)) {
    throw new HttpsError("invalid-argument", "Invalid status");
  }

  try {
    const now = admin.firestore.FieldValue.serverTimestamp();
    
    // Update Firestore
    await db.collection("users").doc(targetUid).update({
      status: newStatus,
      updatedBy: request.auth.uid,
      updatedAt: now
    });

    // If disabled, disable auth account
    if (newStatus === "disabled") {
      await admin.auth().updateUser(targetUid, { disabled: true });
    } else {
      await admin.auth().updateUser(targetUid, { disabled: false });
    }

    // Log Activity
    await db.collection("activities").add({
      userId: request.auth.uid,
      userName: request.auth.token ? (request.auth.token.name || "Admin") : "Admin",
      role: "admin",
      action: `USER_STATUS_CHANGED`,
      entityType: "user",
      entityId: targetUid,
      description: `Changed user status to ${newStatus}`,
      organizationId: "default",
      timestamp: now
    });

    return { success: true };
  } catch (error) {
    logger.error("Error updating user status", error);
    throw new HttpsError("internal", error.message);
  }
});

// 3.1. updateUserPassword (Admin Only) - Multi-Stage Safe Implementation
exports.updateUserPassword = onCall(async (request) => {
  // Stage 1: Function received request
  logger.info("[updateUserPassword] Stage 1: Request received", { hasAuth: !!request.auth });

  // Stage 2 & 3: Request authentication & Admin/super_admin authorization verified
  await checkAdmin(request);
  const callerUid = request.auth ? request.auth.uid : null;
  logger.info("[updateUserPassword] Stage 2 & 3: Authorization verified", { callerUid });

  // Stage 4 & 5: Validate targetUid and newPassword
  const { targetUid, newPassword } = request.data || {};

  if (!targetUid || typeof targetUid !== "string" || targetUid.trim() === "") {
    logger.error("[updateUserPassword] Stage 4 Failed: Invalid targetUid", { targetUid });
    throw new HttpsError("invalid-argument", "Target user ID (targetUid) is required.");
  }

  if (!newPassword || typeof newPassword !== "string" || newPassword.length < 6) {
    logger.error("[updateUserPassword] Stage 5 Failed: Invalid newPassword length");
    throw new HttpsError("invalid-argument", "New password must be at least 6 characters long.");
  }

  logger.info("[updateUserPassword] Stage 4 & 5: Parameters validated successfully", { targetUid });

  // Verify target user exists in Firebase Authentication
  try {
    await admin.auth().getUser(targetUid);
    logger.info("[updateUserPassword] Target user confirmed in Firebase Auth", { targetUid });
  } catch (getUserErr) {
    logger.error("[updateUserPassword] Target user not found in Firebase Auth", { targetUid, error: getUserErr.message });
    throw new HttpsError("not-found", `Target user account (${targetUid}) was not found in Firebase Authentication.`);
  }

  // Stage 6 & 7: Firebase Admin SDK password update attempted & verified
  logger.info("[updateUserPassword] Stage 6: Attempting Firebase Admin SDK password update...", { targetUid });
  try {
    await admin.auth().updateUser(targetUid, { password: newPassword });
    logger.info("[updateUserPassword] Stage 7: Firebase Auth password update SUCCEEDED!", { targetUid });
  } catch (authError) {
    logger.error("[updateUserPassword] Stage 6/7 Failed: Admin SDK updateUser error", { targetUid, code: authError.code, message: authError.message });
    throw new HttpsError("internal", `Firebase Auth password update failed: ${authError.message}`);
  }

  // Stage 8: Firestore metadata & activity update attempted (isolated non-fatal)
  logger.info("[updateUserPassword] Stage 8: Attempting Firestore metadata & activity log update...", { targetUid });
  try {
    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.collection("users").doc(targetUid).set({
      passwordUpdated: true,
      lastPasswordChange: now,
      updatedBy: callerUid,
      updatedAt: now
    }, { merge: true });

    await db.collection("activities").add({
      userId: callerUid,
      userName: request.auth.token ? (request.auth.token.name || "Admin") : "Admin",
      role: "admin",
      action: "USER_PASSWORD_UPDATED",
      entityType: "user",
      entityId: targetUid,
      description: `Updated password for user ${targetUid}`,
      organizationId: "default",
      timestamp: now
    });
    logger.info("[updateUserPassword] Stage 8: Firestore metadata & activity log SUCCEEDED", { targetUid });
  } catch (firestoreError) {
    // Non-fatal warning: Firebase Auth password update ALREADY SUCCEEDED!
    logger.warn("[updateUserPassword] Stage 8 Warning: Firestore update failed non-fatally", { targetUid, error: firestoreError.message });
  }

  // Stage 9: Function returned success
  logger.info("[updateUserPassword] Stage 9: Returning success response", { targetUid });
  return { success: true };
});

// 4. deletePatient (Soft Delete)
exports.deletePatient = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated.");
  }

  const { patientId } = request.data;
  if (!patientId) {
    throw new HttpsError("invalid-argument", "patientId is required");
  }

  try {
    const patientRef = db.collection("patients").doc(patientId);
    const patientDoc = await patientRef.get();

    if (!patientDoc.exists) {
      throw new HttpsError("not-found", "Patient not found");
    }

    const patient = patientDoc.data();
    const role = request.auth.token.role;
    
    // Only Admin or the assigned staff can delete
    if (role !== "admin" && patient.assignedStaffId !== request.auth.uid) {
       throw new HttpsError("permission-denied", "You don't have permission to delete this patient");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    await patientRef.update({
      isDeleted: true,
      deletedAt: now,
      deletedBy: request.auth.uid,
      updatedAt: now,
      updatedBy: request.auth.uid
    });

    // Log Activity
    await db.collection("activities").add({
      userId: request.auth.uid,
      userName: request.auth.token.name || "User",
      role: role,
      action: "PATIENT_DELETED",
      entityType: "patient",
      entityId: patientId,
      description: `Soft deleted patient ${patient.patientName}`,
      organizationId: patient.organizationId || "default",
      timestamp: now
    });

    return { success: true };
  } catch (error) {
    logger.error("Error deleting patient", error);
    throw new HttpsError("internal", error.message);
  }
});

// 5. restorePatient (Admin Only)
exports.restorePatient = onCall(async (request) => {
  await checkAdmin(request);

  const { patientId } = request.data;
  if (!patientId) {
    throw new HttpsError("invalid-argument", "patientId is required");
  }

  try {
    const patientRef = db.collection("patients").doc(patientId);
    const patientDoc = await patientRef.get();

    if (!patientDoc.exists) {
      throw new HttpsError("not-found", "Patient not found");
    }

    const patient = patientDoc.data();
    const now = admin.firestore.FieldValue.serverTimestamp();

    await patientRef.update({
      isDeleted: false,
      deletedAt: admin.firestore.FieldValue.delete(),
      deletedBy: admin.firestore.FieldValue.delete(),
      updatedAt: now,
      updatedBy: request.auth.uid
    });

    // Log Activity
    await db.collection("activities").add({
      userId: request.auth.uid,
      userName: request.auth.token.name || "Admin",
      role: "admin",
      action: "PATIENT_RESTORED",
      entityType: "patient",
      entityId: patientId,
      description: `Restored patient ${patient.patientName}`,
      organizationId: patient.organizationId || "default",
      timestamp: now
    });

    return { success: true };
  } catch (error) {
    logger.error("Error restoring patient", error);
    throw new HttpsError("internal", error.message);
  }
});

const { onDocumentCreated } = require("firebase-functions/v2/firestore");

// 6. Metrics Update: onPatientCreated
exports.onPatientCreated = onDocumentCreated("patients/{patientId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;

  const data = snapshot.data();
  const orgId = data.organizationId || "default";

  const metricsRef = db.collection("system_metrics").doc(`stats_${orgId}`);
  
  try {
    await db.runTransaction(async (transaction) => {
      const doc = await transaction.get(metricsRef);
      if (!doc.exists) {
        transaction.set(metricsRef, { totalPatients: 1 });
      } else {
        transaction.update(metricsRef, {
          totalPatients: admin.firestore.FieldValue.increment(1)
        });
      }
    });
  } catch (error) {
    logger.error("Error updating patient metrics", error);
  }
});

// 7. Metrics Update: onInvoiceCreated
exports.onInvoiceCreated = onDocumentCreated("invoices/{invoiceId}", async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;

  const data = snapshot.data();
  const orgId = data.organizationId || "default";
  const revenue = data.grandTotal || 0;

  const metricsRef = db.collection("system_metrics").doc(`stats_${orgId}`);
  
  try {
    await db.runTransaction(async (transaction) => {
      const doc = await transaction.get(metricsRef);
      if (!doc.exists) {
        transaction.set(metricsRef, { totalRevenue: revenue, totalInvoices: 1 });
      } else {
        transaction.update(metricsRef, {
          totalRevenue: admin.firestore.FieldValue.increment(revenue),
          totalInvoices: admin.firestore.FieldValue.increment(1)
        });
      }
    });
  } catch (error) {
    logger.error("Error updating invoice metrics", error);
  }
});



