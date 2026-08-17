import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Centralized error handling utility that converts technical exceptions
/// (Firebase, Firestore, Network, Auth) into clean, user-friendly messages.
class AppError {
  /// Maps any exception or error object to a clean, user-friendly message.
  /// Logs the raw technical error to debug console for developer inspection.
  static String map(dynamic error, {String? defaultMessage}) {
    debugPrint('[AppError Log] Technical exception caught: $error');

    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No account found for that username.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect password. Please try again.';
        case 'user-disabled':
          return 'This account has been deactivated. Please contact your administrator.';
        case 'too-many-requests':
          return 'Too many failed attempts. Please wait a few moments and try again.';
        case 'requires-recent-login':
          return 'For security reasons, please log out and log in again before updating credentials.';
        case 'weak-password':
          return 'The password is too weak. Please use at least 6 characters.';
        case 'email-already-in-use':
          return 'An account with this username already exists.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        default:
          final cleanMsg = error.message ?? error.code;
          return _cleanRawMessage(cleanMsg);
      }
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'You do not have permission to perform this action.';
        case 'not-found':
          return 'The requested record was not found.';
        case 'already-exists':
          return 'A record with this information already exists.';
        case 'failed-precondition':
          return 'Operation failed due to an invalid system state. Please refresh and try again.';
        case 'unavailable':
          return 'Server is temporarily unavailable. Please check your connection and try again.';
        case 'deadline-exceeded':
          return 'Connection timed out. Please try again.';
        case 'resource-exhausted':
          return 'System resource limit reached. Please try again later.';
        case 'cancelled':
          return 'The operation was cancelled.';
        case 'unauthenticated':
          return 'Your session has expired. Please log in again.';
        default:
          final cleanMsg = error.message ?? error.code;
          return _cleanRawMessage(cleanMsg);
      }
    }

    final rawStr = error.toString();
    return _cleanRawMessage(rawStr, fallback: defaultMessage);
  }

  /// Strips technical prefixes like [cloud_firestore/permission-denied], Exception:, etc.
  static String _cleanRawMessage(String msg, {String? fallback}) {
    var clean = msg;
    clean = clean.replaceAll(RegExp(r'^(Exception|FormatException|StateError):\s*'), '');
    clean = clean.replaceAll(RegExp(r'^\[[\w/-]+\]\s*'), '');
    clean = clean.trim();

    if (clean.isEmpty) {
      return fallback ?? 'An unexpected error occurred. Please try again.';
    }

    if (clean.isNotEmpty) {
      clean = clean[0].toUpperCase() + clean.substring(1);
    }

    return clean;
  }
}
