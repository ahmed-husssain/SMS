import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/errors/app_error.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

class SplashCompletedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setCompleted(bool value) {
    state = value;
  }
}

final splashCompletedProvider = NotifierProvider<SplashCompletedNotifier, bool>(() {
  return SplashCompletedNotifier();
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

class LoginErrorMessageNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setMessage(String? message) => state = message;
}

final loginErrorMessageProvider = NotifierProvider<LoginErrorMessageNotifier, String?>(
  LoginErrorMessageNotifier.new,
);

/// Returns true if the status string represents a deactivated/disabled account.
bool _isDeactivatedStatus(String status) {
  return status == 'deactivated' || status == 'disabled' || status == 'inactive';
}

final userProfileProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    return Stream.value(null);
  }

  return ref.watch(firestoreProvider)
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .map((snapshot) {
        if (!snapshot.exists) {
          return null;
        }
        final data = snapshot.data();
        if (data == null) {
          return null;
        }
        final isDeleted = data['isDeleted'] == true;
        if (isDeleted) {
          return null;
        }
        return data;
      });
});

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(
    auth: ref.watch(firebaseAuthProvider),
    firestore: ref.watch(firestoreProvider),
    ref: ref,
  );
});

class AuthController {
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final Ref? ref;

  AuthController({
    required this.auth,
    required this.firestore,
    this.ref,
  });

  /// Deterministic client-side username-to-email mapping.
  /// E.g. "IT" -> "it@internal.shifa.app", "ADMIN001" -> "admin001@internal.shifa.app"
  String _resolveEmail(String username) {
    return '${username.toLowerCase().trim()}@internal.shifa.app';
  }

  Future<void> login(String username, String password) async {
    final email = _resolveEmail(username);

    try {
      // Authenticate with Firebase Auth directly using deterministic email
      final credential = await auth.signInWithEmailAndPassword(email: email, password: password);

      // Verify user status in Firestore by authenticated UID
      if (credential.user != null) {
        final uid = credential.user!.uid;
        DocumentSnapshot<Map<String, dynamic>> userDoc;
        try {
          userDoc = await firestore.collection('users').doc(uid).get(const GetOptions(source: Source.server));
        } catch (_) {
          userDoc = await firestore.collection('users').doc(uid).get();
        }

        if (userDoc.exists && userDoc.data() != null) {
          final data = userDoc.data()!;
          final isDeleted = data['isDeleted'] == true;
          final status = (data['status'] ?? 'active').toString().toLowerCase();

          if (isDeleted || _isDeactivatedStatus(status)) {
            // Set global error message notifier BEFORE signing out so redirection retains it
            ref?.read(loginErrorMessageProvider.notifier).setMessage(
              'Your account has been deactivated. Please contact an administrator.',
            );
            await auth.signOut();
            throw Exception('Your account has been deactivated. Please contact an administrator.');
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-disabled') {
        ref?.read(loginErrorMessageProvider.notifier).setMessage(
          'Your account has been deactivated. Please contact an administrator.',
        );
        throw Exception('Your account has been deactivated. Please contact an administrator.');
      }
      throw Exception(e.code == 'user-not-found' ? 'No account found for that username.' : 'Incorrect password. Please try again.');
    }
  }

  /// Creates a user account from the Admin's device without logging the Admin out.
  /// Uses a secondary Firebase App instance to avoid session conflicts.
  Future<void> createUserAccount({
    required String username,
    required String password,
    required String name,
    required String phone,
    required String role,
  }) async {
    final email = _resolveEmail(username);
    final cleanUsername = username.trim().toUpperCase();

    // 1. Check if an ACTIVE profile document exists in Firestore
    final existingDoc = await firestore
        .collection('users')
        .where('username', isEqualTo: cleanUsername)
        .limit(1)
        .get();

    if (existingDoc.docs.isNotEmpty) {
      throw Exception("Username '$cleanUsername' is already taken by another active user. Please choose a different username.");
    }

    FirebaseApp? tempApp;
    try {
      tempApp = await Firebase.initializeApp(
        name: 'tempStaffCreation_${DateTime.now().millisecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      
      UserCredential userCredential;
      try {
        userCredential = await tempAuth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          throw Exception("Username '$cleanUsername' is already taken in Firebase Auth. Please choose another username.");
        } else {
          rethrow;
        }
      }

      final uid = userCredential.user!.uid;
      await tempAuth.signOut();

      // Write the staff profile to Firestore (no plaintext password storage)
      await firestore.collection('users').doc(uid).set({
        'uid': uid,
        'username': cleanUsername,
        'name': name,
        'phone': phone,
        'role': role,
        'status': 'active',
        'organizationId': 'default',
        'createdBy': auth.currentUser!.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'isDeleted': false,
      });
    } finally {
      if (tempApp != null) {
        await tempApp.delete();
      }
    }
  }

  /// Soft-deletes a user account in Firestore (Spark Plan compatible).
  /// Immediately deactivates and forces sign-out across all devices.
  Future<void> deleteUserAccount({required String targetUid}) async {
    final userDoc = await firestore.collection('users').doc(targetUid).get();
    if (!userDoc.exists) return;

    final userData = userDoc.data()!;
    final role = (userData['role'] ?? '').toString().toLowerCase();

    final isProtected = userData['isInternalAccount'] == true || userData['isHidden'] == true;

    // 1. Protect internal IT / Master accounts from being deleted
    if (isProtected) {
      throw Exception('This internal account is protected and cannot be deleted.');
    }

    // 2. Protect last remaining Admin account from being deleted
    if (role == 'admin') {
      final allUsersSnap = await firestore.collection('users').get();
      final activeAdminCount = allUsersSnap.docs.where((doc) {
        final data = doc.data();
        final isDeleted = data['isDeleted'] == true;
        final status = (data['status'] ?? 'active').toString().toLowerCase();
        final r = (data['role'] ?? '').toString().toLowerCase();
        return !isDeleted && !_isDeactivatedStatus(status) && r == 'admin';
      }).length;

      if (activeAdminCount <= 1) {
        throw Exception('Cannot delete this account: At least one active Admin account must remain in the system.');
      }
    }

    // 3. Perform soft-delete in Firestore
    await firestore.collection('users').doc(targetUid).update({
      'isDeleted': true,
      'status': 'deactivated',
      'forceLogoutToken': FieldValue.serverTimestamp(),
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Sends a password reset email to the user's email address (Firebase Spark Plan compatible).
  Future<void> sendPasswordResetEmail({required String email}) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) {
      throw Exception('Email address is required to send password reset email.');
    }
    try {
      await auth.sendPasswordResetEmail(email: cleanEmail);
    } on FirebaseAuthException catch (e) {
      throw Exception(AppError.map(e));
    }
  }

  /// Self-service password update for the currently authenticated user.
  Future<void> updateCurrentUserPassword({required String newPassword}) async {
    if (newPassword.trim().length < 6) {
      throw Exception('Password must be at least 6 characters long.');
    }

    final currentUser = auth.currentUser;
    if (currentUser == null) {
      throw Exception('User is not authenticated. Please log in again.');
    }

    try {
      await currentUser.updatePassword(newPassword);
      await firestore.collection('users').doc(currentUser.uid).update({
        'passwordUpdated': true,
        'lastPasswordChange': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseAuthException catch (e) {
      throw Exception(AppError.map(e));
    }
  }

  /// Deactivates a user account. Sets status to 'deactivated' and writes
  /// a forceLogoutToken so all listening devices sign out in real-time.
  Future<void> deactivateUser({required String targetUid}) async {
    final userDoc = await firestore.collection('users').doc(targetUid).get();
    if (!userDoc.exists) {
      throw Exception('User document not found.');
    }

    final userData = userDoc.data()!;
    final role = (userData['role'] ?? '').toString().toLowerCase();

    final isProtected = userData['isInternalAccount'] == true || userData['isHidden'] == true;

    // Protect internal IT / Master accounts from deactivation
    if (isProtected) {
      throw Exception('This internal account is protected and cannot be deactivated.');
    }

    // Protect last remaining admin
    if (role == 'admin') {
      final allUsersSnap = await firestore.collection('users').get();
      final activeAdminCount = allUsersSnap.docs.where((doc) {
        final data = doc.data();
        final isDeleted = data['isDeleted'] == true;
        final status = (data['status'] ?? 'active').toString().toLowerCase();
        final r = (data['role'] ?? '').toString().toLowerCase();
        return !isDeleted && !_isDeactivatedStatus(status) && r == 'admin';
      }).length;

      if (activeAdminCount <= 1) {
        throw Exception('Cannot deactivate: At least one active Admin account must remain.');
      }
    }

    await firestore.collection('users').doc(targetUid).update({
      'status': 'deactivated',
      'forceLogoutToken': FieldValue.serverTimestamp(),
      'deactivatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reactivates a previously deactivated user account.
  Future<void> reactivateUser({required String targetUid}) async {
    final userDoc = await firestore.collection('users').doc(targetUid).get();
    if (!userDoc.exists) {
      throw Exception('User document not found.');
    }

    await firestore.collection('users').doc(targetUid).update({
      'status': 'active',
      'forceLogoutToken': FieldValue.delete(),
      'deactivatedAt': FieldValue.delete(),
      'reactivatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> logout() async {
    await auth.signOut();
  }
}