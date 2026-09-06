import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/services/local_library_store.dart';
import 'package:reader/services/reader_platform_bridge.dart';
import 'package:reader/services/reader_progress_store.dart';
import 'package:reader/services/site_api_client.dart';
import 'package:reader/services/site_session.dart';

class ReaderScreenServices {
  const ReaderScreenServices({
    required this.preferencesController,
    required this.progressStore,
    required this.platformBridge,
    required this.apiClient,
    required this.session,
    required this.localLibraryStore,
  });

  final AppPreferencesController preferencesController;
  final ReaderProgressStore progressStore;
  final ReaderPlatformBridge platformBridge;
  final SiteApiClient apiClient;
  final SiteSession session;
  final LocalLibraryStore localLibraryStore;
}
