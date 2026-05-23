import 'package:connectivity_plus/connectivity_plus.dart';

import 'error_service.dart';

class NetworkService {
  final Connectivity _connectivity = Connectivity();

  Future<bool> isConnected() async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<void> ensureConnected() async {
    if (!await isConnected()) {
      throw AppError.noInternet;
    }
  }
}
