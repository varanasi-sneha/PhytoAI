import 'dart:io';

class AppError {
  final String code;
  final String message;
  final bool retryable;
  final bool fallbackAllowed;

  const AppError({
    required this.code,
    required this.message,
    this.retryable = false,
    this.fallbackAllowed = false,
  });

  @override
  String toString() => message;

  static const AppError noInternet = AppError(
    code: 'no_internet',
    message: 'No internet connection. Please check your network and try again.',
    retryable: true,
    fallbackAllowed: false,
  );

  static const AppError timeout = AppError(
    code: 'timeout',
    message: 'The request timed out. Please try again.',
    retryable: true,
    fallbackAllowed: false,
  );

  static const AppError unclearImage = AppError(
    code: 'unclear_image',
    message: 'Image too blurry',
    retryable: true,
    fallbackAllowed: true,
  );

  static const AppError notLeaf = AppError(
    code: 'not_a_leaf',
    message: 'Disease not recognized',
    retryable: true,
    fallbackAllowed: false,
  );

  static const AppError invalidImage = AppError(
    code: 'invalid_image',
    message: 'The selected image is invalid. Please choose a different photo.',
    retryable: true,
    fallbackAllowed: false,
  );

  static const AppError modelUnavailable = AppError(
    code: 'model_unavailable',
    message: 'Model initialization failed.',
    retryable: true,
    fallbackAllowed: false,
  );

  static const AppError lowConfidence = AppError(
    code: 'low_confidence',
    message: 'Prediction uncertain',
    retryable: true,
    fallbackAllowed: true,
  );

  static const AppError backendFailure = AppError(
    code: 'backend_failure',
    message: 'Server unavailable. Please try again later.',
    retryable: true,
    fallbackAllowed: false,
  );

  static const AppError unknown = AppError(
    code: 'unknown_error',
    message: 'Disease not recognized',
    retryable: true,
    fallbackAllowed: true,
  );

  static const AppError inferenceFailure = AppError(
    code: 'inference_failure',
    message: 'Could not process image.',
    retryable: true,
    fallbackAllowed: false,
  );
}

class ErrorService {
  static AppError parse(Object error) {
    if (error is AppError) {
      return error;
    }

    final message = error.toString().toLowerCase();
    
    // Check for offline prediction issues first
    if (message.contains('model_uninitialized') || message.contains('model unavailable') || message.contains('initialization failed')) {
      return AppError.modelUnavailable;
    }
    
    if (message.contains('unclear_image') || message.contains('blurry') || message.contains('too blurry')) {
      return AppError.unclearImage;
    }

    if (message.contains('low_confidence') || message.contains('prediction uncertain') || message.contains('low confidence')) {
      return AppError.lowConfidence;
    }

    if (message.contains('not_a_leaf') || message.contains('not a leaf') || message.contains('not_a_spinach_leaf') || message.contains('unknown')) {
      return AppError.notLeaf;
    }

    if (message.contains('invalid_image') || message.contains('invalid image')) {
      return AppError.invalidImage;
    }

    if (message.contains('inference_failed') || message.contains('could not process') || message.contains('inference failure')) {
      return AppError.inferenceFailure;
    }

    if (error is SocketException) {
      return AppError.backendFailure; // Map to generic backend failure rather than internet warning for local operations
    }

    if (error is HttpException) {
      if (message.contains('not_a_leaf') || message.contains('not a leaf') || message.contains('not_a_spinach_leaf')) {
        return AppError.notLeaf;
      }
      if (message.contains('unclear_image') || message.contains('blurry')) {
        return AppError.unclearImage;
      }
      if (message.contains('invalid_image') || message.contains('invalid image')) {
        return AppError.invalidImage;
      }
      if (message.contains('timed out') || message.contains('timeout')) {
        return AppError.timeout;
      }
      return AppError.backendFailure;
    }

    if (message.contains('timeout')) {
      return AppError.timeout;
    }

    return AppError.unknown;
  }
}
