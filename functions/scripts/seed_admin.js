/**
 * Standalone Administrative Seeding Script for Internal IT Admin Account
 *
 * SAFETY GUARDRAILS:
 * 1. Default mode is DRY-RUN. Real mutations require the explicit '--execute' flag.
 * 2. Never accepts or contains hardcoded passwords. Requires IT_ADMIN_PASSWORD env variable.
 * 3. Never deletes arbitrary or non-IT user data.
 * 4. 100% idempotent: running multiple times preserves canonical UID and does not duplicate data.
 * 5. Standalone server-side execution only: NEVER import in Flutter or client code.
 *
 * Usage:
 *   Dry Run (Default):
 *     node functions/scripts/seed_admin.js
 *     node functions/scripts/seed_admin.js --dry-run
 *
 *   Execute:
 *     IT_ADMIN_PASSWORD="your-secure-password" node functions/scripts/seed_admin.js --execute
 */

const path = require("path");
const admin = require("firebase-admin");

// 1. Load service account credentials securely
const serviceAccountPath = path.resolve(__dirname, "../service-account.json");
let serviceAccount;
try {
  serviceAccount = require(serviceAccountPath);
} catch (err) {
  console.error("❌ CRITICAL ERROR: Unable to load service-account.json from:", serviceAccountPath);
  console.error("Ensure service-account.json is present in the functions/ directory.");
  process.exit(1);
}

// 2. Validate Firebase Project ID
const EXPECTED_PROJECT_ID = "shifamangementapp";
if (!serviceAccount.project_id || serviceAccount.project_id !== EXPECTED_PROJECT_ID) {
  console.error(`❌ SAFETY CHECK FAILED: Project ID mismatch. Expected '${EXPECTED_PROJECT_ID}', but found '${serviceAccount.project_id}'.`);
  process.exit(1);
}

// 3. Initialize Firebase Admin SDK
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: EXPECTED_PROJECT_ID,
});

const auth = admin.auth();
const db = admin.firestore();

// 4. Canonical IT Account Specifications
const CANONICAL_CONFIG = {
  username: "IT",
  email: "it@internal.shifa.app",
  displayName: "Internal IT Support",
  role: "admin",
  organizationId: "default",
  isInternalAccount: true,
  isHidden: true,
  status: "active",
  isDeleted: false,
};

// Known stale/legacy aliases and orphan documents for deterministic reconciliation
const STALE_EMAIL_ALIASES = [
  "it2026@internal.shifa.app",
  "it_admin@internal.shifa.app",
  "it_master@internal.shifa.app",
  "it_support@internal.shifa.app",
];
const KNOWN_ORPHAN_UIDS = [
  "1BvAsz7VxFdRK4aEBsj6QRqTUCQ2",
];

async function run() {
  const args = process.argv.slice(2);
  const isExecute = args.includes("--execute");
  const isDryRun = !isExecute || args.includes("--dry-run");

  console.log("===============================================================");
  console.log(`🔒 Internal IT Administrator Seeding Script [${isDryRun ? "DRY-RUN MODE" : "EXECUTE MODE"}]`);
  console.log(`🎯 Target Project: ${EXPECTED_PROJECT_ID}`);
  console.log(`📧 Canonical Email: ${CANONICAL_CONFIG.email}`);
  console.log("===============================================================\n");

  let password = process.env.IT_ADMIN_PASSWORD;

  if (isExecute) {
    if (!password || password.trim().length < 6) {
      console.error("❌ CRITICAL ERROR: Password required for execution.");
      console.error("Set the IT_ADMIN_PASSWORD environment variable with at least 6 characters.");
      console.error('Example: IT_ADMIN_PASSWORD="YourPassword" node functions/scripts/seed_admin.js --execute');
      process.exit(1);
    }
    password = password.trim();
  }

  // ─── STEP 1: Inspect Firebase Authentication ────────────────────────
  console.log("🔍 [Phase 1] Inspecting Firebase Authentication...");
  let canonicalAuthUser = null;
  const staleAuthUsersToDelete = [];

  try {
    canonicalAuthUser = await auth.getUserByEmail(CANONICAL_CONFIG.email);
    console.log(`  ℹ️ Found existing canonical Auth account: UID = ${canonicalAuthUser.uid}`);
  } catch (err) {
    if (err.code === "auth/user-not-found") {
      console.log(`  ℹ️ Canonical Auth account (${CANONICAL_CONFIG.email}) does NOT exist yet.`);
    } else {
      throw err;
    }
  }

  for (const alias of STALE_EMAIL_ALIASES) {
    try {
      const staleUser = await auth.getUserByEmail(alias);
      if (!canonicalAuthUser || staleUser.uid !== canonicalAuthUser.uid) {
        console.log(`  ⚠️ Found stale Auth account (${alias}): UID = ${staleUser.uid}`);
        staleAuthUsersToDelete.push(staleUser);
      }
    } catch (_) {
      // Alias does not exist in Auth
    }
  }

  // ─── STEP 2: Inspect Firestore Database ─────────────────────────────
  console.log("\n🔍 [Phase 2] Inspecting Firestore Database (users collection)...");
  let canonicalFirestoreDoc = null;
  const orphanFirestoreDocsToDelete = [];

  if (canonicalAuthUser) {
    const docSnap = await db.collection("users").doc(canonicalAuthUser.uid).get();
    if (docSnap.exists) {
      canonicalFirestoreDoc = docSnap.data();
      console.log(`  ℹ️ Found Firestore profile matching canonical UID: users/${canonicalAuthUser.uid}`);
    }
  }

  for (const orphanUid of KNOWN_ORPHAN_UIDS) {
    const orphanSnap = await db.collection("users").doc(orphanUid).get();
    if (orphanSnap.exists) {
      const data = orphanSnap.data() || {};
      if (data.username === "IT" || data.isInternalAccount === true) {
        console.log(`  ⚠️ Found orphan IT Firestore profile: users/${orphanUid}`);
        orphanFirestoreDocsToDelete.push({ id: orphanUid, data });
      }
    }
  }

  // Also check for any extra Firestore docs with username == 'IT' that do not match canonical UID
  const itUsernameSnap = await db.collection("users").where("username", "==", "IT").get();
  for (const doc of itUsernameSnap.docs) {
    const uid = doc.id;
    if (canonicalAuthUser && uid === canonicalAuthUser.uid) continue;
    if (orphanFirestoreDocsToDelete.some((d) => d.id === uid)) continue;

    // Check if this doc has a valid active Auth account
    let hasValidAuth = false;
    try {
      await auth.getUser(uid);
      hasValidAuth = true;
    } catch (_) {}

    if (!hasValidAuth) {
      console.log(`  ⚠️ Found unlinked IT Firestore document: users/${uid}`);
      orphanFirestoreDocsToDelete.push({ id: uid, data: doc.data() });
    }
  }

  // ─── STEP 3: Plan / Execute Actions ─────────────────────────────────
  console.log("\n📋 [Summary of Actions]");
  console.log(`  - Stale Auth accounts to remove: ${staleAuthUsersToDelete.length}`);
  staleAuthUsersToDelete.forEach((u) => console.log(`      • Auth UID: ${u.uid} (${u.email})`));

  console.log(`  - Orphan Firestore profiles to remove: ${orphanFirestoreDocsToDelete.length}`);
  orphanFirestoreDocsToDelete.forEach((d) => console.log(`      • Firestore doc: users/${d.id} (${d.data.username || "Unknown"})`));

  if (canonicalAuthUser) {
    console.log(`  - Canonical Auth account: REUSE existing UID (${canonicalAuthUser.uid}) & update credentials/claims`);
  } else {
    console.log(`  - Canonical Auth account: CREATE new user for ${CANONICAL_CONFIG.email}`);
  }
  console.log(`  - Canonical Firestore profile: UPSERT users/{canonicalUid}`);

  if (isDryRun) {
    console.log("\n===============================================================");
    console.log("🛡️ DRY-RUN COMPLETE: No changes were made to Firebase.");
    console.log("To execute these changes, run:");
    console.log('  IT_ADMIN_PASSWORD="<password>" node functions/scripts/seed_admin.js --execute');
    console.log("===============================================================\n");
    process.exit(0);
  }

  // ─── REAL EXECUTION ─────────────────────────────────────────────────
  console.log("\n🚀 [Phase 3] Executing Database & Auth Mutations...");

  // 1. Remove stale Auth users
  for (const user of staleAuthUsersToDelete) {
    console.log(`  🗑️ Deleting stale Auth account: ${user.uid} (${user.email})...`);
    await auth.deleteUser(user.uid);
  }

  // 2. Remove orphan Firestore documents
  for (const doc of orphanFirestoreDocsToDelete) {
    console.log(`  🗑️ Deleting orphan Firestore doc: users/${doc.id}...`);
    await db.collection("users").doc(doc.id).delete();
  }

  // 3. Create or update canonical Auth user
  let finalUid;
  if (canonicalAuthUser) {
    finalUid = canonicalAuthUser.uid;
    console.log(`  🔄 Updating password and profile for existing Auth user (${finalUid})...`);
    await auth.updateUser(finalUid, {
      password: password,
      displayName: CANONICAL_CONFIG.displayName,
      disabled: false,
    });
  } else {
    console.log(`  ✨ Creating canonical Auth user (${CANONICAL_CONFIG.email})...`);
    const newRecord = await auth.createUser({
      email: CANONICAL_CONFIG.email,
      password: password,
      displayName: CANONICAL_CONFIG.displayName,
      disabled: false,
    });
    finalUid = newRecord.uid;
  }

  // 4. Set custom claims on canonical account
  console.log(`  🛡️ Setting custom claims on ${finalUid} (role: admin)... `);
  await auth.setCustomUserClaims(finalUid, {
    role: "admin",
    organizationId: "default",
  });

  // 5. Upsert Firestore user document
  console.log(`  📝 Upserting Firestore profile at users/${finalUid}...`);
  const profileRef = db.collection("users").doc(finalUid);
  const existingProfileSnap = await profileRef.get();

  const firestoreData = {
    uid: finalUid,
    username: CANONICAL_CONFIG.username,
    name: CANONICAL_CONFIG.displayName,
    role: CANONICAL_CONFIG.role,
    isInternalAccount: CANONICAL_CONFIG.isInternalAccount,
    isHidden: CANONICAL_CONFIG.isHidden,
    status: CANONICAL_CONFIG.status,
    isDeleted: CANONICAL_CONFIG.isDeleted,
    organizationId: CANONICAL_CONFIG.organizationId,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (!existingProfileSnap.exists) {
    firestoreData.createdAt = admin.firestore.FieldValue.serverTimestamp();
  }

  await profileRef.set(firestoreData, { merge: true });

  // ─── STEP 4: Read-Back Verification ─────────────────────────────────
  console.log("\n🔍 [Phase 4] Performing Read-Back Verification...");
  const verifiedAuthUser = await auth.getUser(finalUid);
  const verifiedFirestoreSnap = await db.collection("users").doc(finalUid).get();
  const verifiedData = verifiedFirestoreSnap.data() || {};

  const authValid = verifiedAuthUser.email === CANONICAL_CONFIG.email &&
                    verifiedAuthUser.disabled === false &&
                    verifiedAuthUser.customClaims?.role === "admin";

  const firestoreValid = verifiedFirestoreSnap.exists &&
                         verifiedData.uid === finalUid &&
                         verifiedData.username === "IT" &&
                         verifiedData.role === "admin" &&
                         verifiedData.status === "active" &&
                         verifiedData.isDeleted === false &&
                         verifiedData.isInternalAccount === true &&
                         verifiedData.isHidden === true;

  if (!authValid || !firestoreValid) {
    console.error("❌ VERIFICATION FAILED! Inconsistency detected between Auth and Firestore.");
    console.error("Auth valid:", authValid, "Firestore valid:", firestoreValid);
    process.exit(1);
  }

  console.log("  ✅ Firebase Auth: Verified (Email: it@internal.shifa.app, Claims: { role: 'admin' })");
  console.log("  ✅ Firestore Document: Verified (Path: users/" + finalUid + ", Role: admin, Status: active)");
  console.log("  ✅ Password: Fully updated without storing in database or logs.");

  console.log("\n===============================================================");
  console.log("🎉 INTERNAL IT ADMIN SEEDED AND VERIFIED SUCCESSFULLY!");
  console.log(`   Username: ${CANONICAL_CONFIG.username}`);
  console.log(`   Email:    ${CANONICAL_CONFIG.email}`);
  console.log(`   UID:      ${finalUid}`);
  console.log("===============================================================\n");

  process.exit(0);
}

run().catch((err) => {
  console.error("\n❌ UNEXPECTED ERROR DURING SEEDING:", err);
  process.exit(1);
});
