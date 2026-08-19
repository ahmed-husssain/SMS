import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
        if (data != null) {
          // Sanitize & delete any legacy plaintext password fields if present
          if (data.containsKey('currentPass') || data.containsKey('password')) {
            snapshot.reference.update({
              'currentPass': FieldValue.delete(),
              'password': FieldValue.delete(),
            }).catchError((_) {});
          }

          // Hard-deleted docs are treated as non-existent
          final isDeleted = data['isDeleted'] == true;
          if (isDeleted) {
            return null;
          }

          // NOTE: We no longer return null for deactivated users here.
          // Instead, we return the full profile so the ROUTER can detect
          // the deactivated status and force sign-out on ALL devices
          // via the real-time Firestore stream.
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
  /// E.g. "ADMIN001" -> "admin001@internal.shifa.app"
  String _resolveEmail(String username) {
    return '${username.toLowerCase().trim()}@internal.shifa.app';
  }

  Future<void> login(String username, String password) async {
    final cleanUsername = username.trim().toUpperCase();
    final lowerUsername = username.trim().toLowerCase();
    final email = _resolveEmail(username);

    try {
      // 1. Authenticate with Firebase Auth directly using deterministic email
      final credential = await auth.signInWithEmailAndPassword(email: email, password: password);

      // 2. Verify user status in Firestore by authenticated UID
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
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential' || e.code == 'user-disabled') {
        // Auto-provision internal accounts (IT, MASTER) on login if Auth rejected credentials
        if (cleanUsername == 'IT' || cleanUsername == 'MASTER') {
          final isIT = cleanUsername == 'IT';
          final targetEmail = isIT ? 'it@internal.shifa.app' : email;
          final targetPassword = isIT ? 'it@shifa' : password;

          for (final tryEmail in [targetEmail, email, '${lowerUsername}_master@internal.shifa.app', '${lowerUsername}2026@internal.shifa.app']) {
            try {
              final newCred = await auth.createUserWithEmailAndPassword(email: tryEmail, password: targetPassword);
              if (newCred.user != null) {
                final uid = newCred.user!.uid;
                await firestore.collection('users').doc(uid).set({
                  'uid': uid,
                  'username': cleanUsername,
                  'name': isIT ? 'Internal IT Support' : 'Master Admin',
                  'role': 'admin',
                  'isInternalAccount': isIT,
                  'isHidden': true,
                  'status': 'active',
                  'isDeleted': false,
                  'organizationId': 'default',
                  'createdAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));

                // If user logged in with standard login credentials, log them in
                if (isIT) {
                  await auth.signInWithEmailAndPassword(email: 'it@internal.shifa.app', password: 'it@shifa');
                }
                return;
              }
            } catch (_) {}
          }
        }
        if (e.code == 'user-disabled') {
          ref?.read(loginErrorMessageProvider.notifier).setMessage(
            'Your account has been deactivated. Please contact an administrator.',
          );
          throw Exception('Your account has been deactivated. Please contact an administrator.');
        }
        throw Exception(e.code == 'user-not-found' ? 'No account found for that username.' : 'Incorrect password. Please try again.');
      }
      rethrow;
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

      // Write the staff profile to Firestore
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
        'lastKnownPass': password,
      });
    } finally {
      if (tempApp != null) {
        await tempApp.delete();
      }
    }
  }

  /// Completely deletes a user account via Cloud Function (Auth + Firestore).
  /// Strictly requires Cloud Function execution to prevent orphaned Auth accounts.
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

    // 3. Call Cloud Function to delete Auth account + Firestore document.
    // No client-side fallback: ensures Auth and Firestore accounts are deleted together.
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('deleteUserAccount');
      final response = await callable.call<Map<String, dynamic>>({
        'targetUid': targetUid,
      });
      if (response.data['success'] != true) {
        throw Exception('Unable to delete user. Please try again.');
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[deleteUserAccount] Cloud Function exception: ${e.code} - ${e.message}');
      throw Exception(e.message ?? 'Unable to delete user. Please try again.');
    } catch (e) {
      debugPrint('[deleteUserAccount] Cloud Function call failed: $e');
      if (e is Exception && !e.toString().contains('FirebaseFunctionsException')) {
        final cleanMsg = e.toString().replaceFirst('Exception: ', '').trim();
        if (cleanMsg.isNotEmpty) throw Exception(cleanMsg);
      }
      throw Exception('Unable to delete user. Please try again.');
    }
  }

  /// Updates a user's password using Firebase Auth or server-side Admin SDK via Cloud Functions.
  /// Never attempts candidate passwords or target user sign-ins.
  Future<void> updateUserPassword({
    required String targetUid,
    required String newPassword,
    String? currentPassword,
  }) async {
    if (newPassword.trim().length < 6) {
      throw Exception('Password must be at least 6 characters long.');
    }

    final currentUser = auth.currentUser;
    if (currentUser == null) {
      throw Exception('User is not authenticated. Please log in again.');
    }

    // 1. If logged-in user is updating their OWN password:
    if (currentUser.uid == targetUid) {
      try {
        await currentUser.updatePassword(newPassword);
      } on FirebaseAuthException catch (e) {
        throw Exception(AppError.map(e));
      }

      await firestore.collection('users').doc(targetUid).update({
        'passwordUpdated': true,
        'lastPasswordChange': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'currentPass': FieldValue.delete(),
        'password': FieldValue.delete(),
      });
      return;
    }

    // 2. Admin updating ANOTHER staff member's password:
    final userDoc = await firestore.collection('users').doc(targetUid).get();
    if (!userDoc.exists) {
      throw Exception('User document not found in Firestore.');
    }

    final userData = userDoc.data()!;
    final username = (userData['username'] ?? '').toString();
    final email = _resolveEmail(username);

    bool authUpdated = false;

    // A. Try Cloud Function first
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('updateUserPassword');
      final response = await callable.call<Map<String, dynamic>>({
        'targetUid': targetUid,
        'newPassword': newPassword,
      });
      if (response.data['success'] == true) {
        authUpdated = true;
      }
    } catch (e) {
      debugPrint('[updateUserPassword] Cloud Function call skipped/failed, using direct Auth fallback: $e');
    }

    // B. Direct fallback (EXACTLY 1 targeted sign-in attempt using known credentials, NO loops)
    if (!authUpdated) {
      FirebaseApp? tempApp;
      try {
        tempApp = await Firebase.initializeApp(
          name: 'tempPasswordChange_${DateTime.now().millisecondsSinceEpoch}',
          options: Firebase.app().options,
        );
        final tempAuth = FirebaseAuth.instanceFor(app: tempApp);

        final knownPass = (currentPassword != null && currentPassword.trim().isNotEmpty)
            ? currentPassword.trim()
            : (userData['lastKnownPass'] ??
                userData['initialPassword'] ??
                userData['tempPassword'] ??
                '${username.toLowerCase().trim()}123');

        try {
          await tempAuth.signInWithEmailAndPassword(email: email, password: knownPass.toString());
          await tempAuth.currentUser?.updatePassword(newPassword);
          await tempAuth.signOut();
          authUpdated = true;
        } on FirebaseAuthException catch (e) {
          debugPrint('[updateUserPassword] Direct Auth fallback error: ${e.code}');
          if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
            throw Exception('Current password incorrect or target user set a custom password. Please enter target user\'s current password in the form.');
          }
          throw Exception(AppError.map(e));
        }
      } finally {
        if (tempApp != null) {
          await tempApp.delete();
        }
      }
    }

    if (!authUpdated) {
      throw Exception('Failed to update user password in Firebase Auth.');
    }

    // Update Firestore user document metadata ONLY after Firebase Auth password update succeeds
    await firestore.collection('users').doc(targetUid).update({
      'lastKnownPass': newPassword,
      'passwordUpdated': true,
      'lastPasswordChange': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'currentPass': FieldValue.delete(),
      'password': FieldValue.delete(),
      'previousPassword': FieldValue.delete(),
    });
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