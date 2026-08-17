const admin = require("firebase-admin");
const serviceAccount = require("./service-account.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function seedAdmin() {
  const username = "ADMIN001";
  const internalEmail = "admin001@internal.shifa.app";
  const password = "AdminPassword123!"; // Secure password for initial login
  const name = "Super Admin";

  try {
    let userRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(internalEmail);
      console.log("Admin user already exists in Firebase Auth:", userRecord.uid);
    } catch (e) {
      if (e.code === 'auth/user-not-found') {
        userRecord = await admin.auth().createUser({
          email: internalEmail,
          password: password,
          displayName: name,
        });
        console.log("Created Admin user in Firebase Auth:", userRecord.uid);
      } else {
        throw e;
      }
    }

    // Set Custom Claims for Admin
    await admin.auth().setCustomUserClaims(userRecord.uid, {
      role: "admin",
      organizationId: "default"
    });
    console.log("Custom claims set to { role: 'admin' }");

    // Create Firestore Document
    await db.collection("users").doc(userRecord.uid).set({
      uid: userRecord.uid,
      username: username,
      name: name,
      phone: "+1234567890",
      role: "admin",
      status: "active",
      organizationId: "default",
      createdBy: "system",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      isDeleted: false
    });
    console.log("Firestore user profile created.");

    console.log("\n=================================");
    console.log("Admin Bootstrapped Successfully!");
    console.log("Username: " + username);
    console.log("Password: " + password);
    console.log("=================================\n");
    
    process.exit(0);
  } catch (error) {
    console.error("Error seeding admin:", error);
    process.exit(1);
  }
}

seedAdmin();
