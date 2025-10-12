// Conditional export: use web implementation when running on web, otherwise use stub.
export 'xiaozhi_mic_stub.dart'
    if (dart.library.html) 'xiaozhi_mic_web_impl.dart';
