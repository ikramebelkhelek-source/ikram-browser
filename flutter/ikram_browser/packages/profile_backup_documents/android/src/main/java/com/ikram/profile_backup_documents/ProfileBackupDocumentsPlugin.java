package com.ikram.profile_backup_documents;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** No cookies, WebViews, filesystem paths, cached copies or persistent URI grants. */
public final class ProfileBackupDocumentsPlugin implements FlutterPlugin,
        MethodChannel.MethodCallHandler, ActivityAware, ActivityResultListener {
    static final int REQUEST = 0x494B;
    // One UTF-16 code unit uses at most three UTF-8 bytes. The Dart schema also
    // enforces its character limit; this cap bounds native reads before decoding.
    static final int MAX_BYTES = 3 * 1024 * 1024;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private MethodChannel channel;
    private ActivityPluginBinding binding;
    private Activity activity;
    private MethodChannel.Result pending;
    private byte[] exportBytes;
    private int maxBytes;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding engine) {
        channel = new MethodChannel(engine.getBinaryMessenger(),
                "com.ikram/profile_backup_documents");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding engine) {
        channel.setMethodCallHandler(null);
        failPending("unavailable", "Document access was interrupted.");
        io.shutdownNow();
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding value) {
        binding = value;
        activity = value.getActivity();
        value.addActivityResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detach();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding value) {
        onAttachedToActivity(value);
    }

    @Override
    public void onDetachedFromActivity() {
        detach();
        failPending("unavailable", "Document access was interrupted.");
    }

    private void detach() {
        if (binding != null) binding.removeActivityResultListener(this);
        binding = null;
        activity = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (!call.method.equals("save") && !call.method.equals("open")) {
            result.notImplemented();
            return;
        }
        if (pending != null) {
            result.error("busy", "A document operation is already active.", null);
            return;
        }
        if (activity == null) {
            result.error("unavailable", "No activity is available.", null);
            return;
        }
        final boolean saving = call.method.equals("save");
        final Object bytes = call.argument("bytes");
        final Object limit = call.argument("maxBytes");
        if ((saving && (!(bytes instanceof byte[]) || ((byte[]) bytes).length > MAX_BYTES))
                || (!saving && (!(limit instanceof Integer)
                    || (Integer) limit < 1 || (Integer) limit > MAX_BYTES))) {
            result.error("invalid_arguments", "Invalid document size.", null);
            return;
        }
        pending = result;
        exportBytes = saving ? (byte[]) bytes : null;
        maxBytes = saving ? 0 : (Integer) limit;
        Intent intent = new Intent(saving ? Intent.ACTION_CREATE_DOCUMENT : Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        // Opening accepts JSON from providers that label it text/plain or
        // application/octet-stream too. The app validates the actual content.
        intent.setType(saving ? "application/json" : "*/*");
        if (saving) intent.putExtra(Intent.EXTRA_TITLE, "ikram-profiles.json");
        try {
            activity.startActivityForResult(intent, REQUEST);
        } catch (RuntimeException error) {
            failPending("unavailable", "The system document picker could not open.");
        }
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQUEST || pending == null) return false;
        if (resultCode == Activity.RESULT_CANCELED) {
            finish(pending, null, null);
            return true;
        }
        Uri uri = data == null ? null : data.getData();
        if (resultCode != Activity.RESULT_OK || uri == null || activity == null) {
            failPending("unavailable", "The selected document is unavailable.");
            return true;
        }
        final MethodChannel.Result result = pending;
        final byte[] bytes = exportBytes;
        final int limit = maxBytes;
        final android.content.ContentResolver resolver = activity.getContentResolver();
        io.execute(() -> {
            try {
                Object value;
                if (bytes != null) {
                    // "wt" truncates an explicitly selected existing document.
                    // A provider returning null must never count as success.
                    try (OutputStream output = resolver.openOutputStream(uri, "wt")) {
                        if (output == null) throw new IOException("No output stream.");
                        output.write(bytes);
                        output.flush();
                    }
                    value = true;
                } else {
                    try (InputStream input = resolver.openInputStream(uri)) {
                        if (input == null) throw new IOException("No input stream.");
                        value = readBounded(input, limit);
                    }
                }
                final Object completed = value;
                main.post(() -> finish(result, completed, null));
            } catch (Exception error) {
                // Never send provider exception text (paths or file contents)
                // back to Flutter, the UI, or logs.
                main.post(() -> finish(result, null,
                        error instanceof TooLargeException ? "too_large" : "storage_error"));
            }
        });
        return true;
    }

    static byte[] readBounded(InputStream input, int limit) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int count;
        while ((count = input.read(buffer, 0, Math.min(buffer.length, limit - output.size() + 1))) != -1) {
            if (count > limit - output.size()) throw new TooLargeException();
            output.write(buffer, 0, count);
        }
        return output.toByteArray();
    }

    static final class TooLargeException extends IOException {}

    private void failPending(String code, String message) {
        if (pending == null) return;
        MethodChannel.Result result = pending;
        pending = null;
        exportBytes = null;
        result.error(code, message, null);
    }

    private void finish(MethodChannel.Result result, Object value, String error) {
        if (pending != result) return; // Activity/engine may have detached during IO.
        pending = null;
        exportBytes = null;
        if (error == null) result.success(value);
        else result.error(error, "The document could not be read or fully saved.", null);
    }
}
