package dev.flutter.plugins.integration_test;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Release-only link shim for Flutter 3.44's generated plugin registrant.
 *
 * integration_test is a dev dependency and is intentionally omitted from the
 * release classpath by Flutter's Gradle plugin. The registrant is generated in
 * the main source set, however, so it still references the plugin class. Keep
 * the actual integration-test plugin in debug/profile and use this no-op type
 * only for release builds; no test channel is exposed in the shipped app.
 */
public final class IntegrationTestPlugin implements FlutterPlugin {
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {}

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {}
}
