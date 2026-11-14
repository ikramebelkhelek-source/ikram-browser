package com.ikram.profile_backup_documents;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

import android.app.Activity;
import android.content.ContentProvider;
import android.content.ActivityNotFoundException;
import android.content.ContentValues;
import android.content.Intent;
import android.content.pm.ProviderInfo;
import android.database.Cursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowContentResolver;
import org.robolectric.shadows.ShadowLooper;
import org.robolectric.Shadows;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.HashMap;
import java.util.Map;

/** Drives actual Android intents and ContentResolver IO, not a Dart channel mock.
 * Robolectric supplies the Android runtime; no emulator or personal storage. */
@RunWith(RobolectricTestRunner.class)
@Config(sdk = {24, 35}, manifest = Config.NONE)
public class ProfileBackupDocumentsPluginTest {
    private static final Uri URI = Uri.parse("content://backup-test/profile.json");
    private ProfileBackupDocumentsPlugin plugin;
    private FlutterPlugin.FlutterPluginBinding engine;
    private Activity activity;
    private TestProvider provider;

    public static final class TestProvider extends ContentProvider {
        File file;
        boolean unavailable;
        boolean readOnly;
        int opened;
        @Override public boolean onCreate() { return true; }
        @Override public String getType(Uri uri) { return "application/json"; }
        @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { return null; }
        @Override public Uri insert(Uri u, ContentValues v) { throw new UnsupportedOperationException(); }
        @Override public int delete(Uri u, String s, String[] a) { return 0; }
        @Override public int update(Uri u, ContentValues v, String s, String[] a) { return 0; }
        @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
            opened++;
            if (unavailable) throw new FileNotFoundException("Synthetic disconnected storage");
            return ParcelFileDescriptor.open(file,
                    readOnly ? ParcelFileDescriptor.MODE_READ_ONLY : ParcelFileDescriptor.parseMode(mode));
        }
    }

    public static final class NoDocumentsActivity extends Activity {
        @Override public void startActivityForResult(Intent intent, int request) {
            throw new ActivityNotFoundException("Synthetic missing document picker");
        }
    }

    private static final class Result implements MethodChannel.Result {
        int completions;
        Object value;
        String error;
        @Override public void success(Object result) { completions++; value = result; }
        @Override public void error(String code, String message, Object details) {
            completions++; error = code;
        }
        @Override public void notImplemented() { fail("Unexpected method"); }
    }

    @Before public void setup() throws Exception {
        activity = Robolectric.buildActivity(Activity.class).setup().get();
        engine = mock(FlutterPlugin.FlutterPluginBinding.class);
        when(engine.getBinaryMessenger()).thenReturn(mock(BinaryMessenger.class));
        plugin = new ProfileBackupDocumentsPlugin();
        plugin.onAttachedToEngine(engine);
        attach(activity);
        provider = new TestProvider();
        provider.file = File.createTempFile("synthetic-backup", ".json", activity.getCacheDir());
        ProviderInfo info = new ProviderInfo();
        info.authority = "backup-test";
        provider.attachInfo(activity, info);
        ShadowContentResolver.registerProviderInternal(info.authority, provider);
    }

    private void attach(Activity host) {
        ActivityPluginBinding binding = mock(ActivityPluginBinding.class);
        when(binding.getActivity()).thenReturn(host);
        plugin.onAttachedToActivity(binding);
        verify(binding).addActivityResultListener(plugin);
    }

    @After public void teardown() {
        plugin.onDetachedFromActivity();
        plugin.onDetachedFromEngine(engine);
        provider.file.delete();
    }

    private Result start(String method, byte[] bytes) {
        Result result = new Result();
        Map<String, Object> args = new HashMap<>();
        if (bytes != null) args.put("bytes", bytes);
        args.put("maxBytes", ProfileBackupDocumentsPlugin.MAX_BYTES);
        plugin.onMethodCall(new MethodCall(method, args), result);
        return result;
    }

    private void complete(Result result) throws Exception {
        assertTrue(plugin.onActivityResult(ProfileBackupDocumentsPlugin.REQUEST,
                Activity.RESULT_OK, new Intent().setData(URI)));
        long deadline = System.nanoTime() + 5_000_000_000L;
        while (result.completions == 0 && System.nanoTime() < deadline) {
            ShadowLooper.idleMainLooper();
            Thread.sleep(5);
        }
        assertEquals("Document callback must settle exactly once", 1, result.completions);
    }

    @Test public void systemIntentsUseScopedAccessAndCancellationNeverTouchesProvider() {
        for (String method : new String[]{"save", "open"}) {
            Result result = start(method, method.equals("save") ? new byte[]{1} : null);
            Intent intent = Shadows.shadowOf(activity).getNextStartedActivityForResult().intent;
            assertEquals(method.equals("save") ? Intent.ACTION_CREATE_DOCUMENT
                    : Intent.ACTION_OPEN_DOCUMENT, intent.getAction());
            assertTrue(intent.hasCategory(Intent.CATEGORY_OPENABLE));
            assertEquals(method.equals("save") ? "application/json" : "*/*", intent.getType());
            assertEquals(0, intent.getFlags() & Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
            assertTrue(plugin.onActivityResult(ProfileBackupDocumentsPlugin.REQUEST,
                    Activity.RESULT_CANCELED, null));
            assertEquals(1, result.completions);
            assertNull(result.error);
            assertNull(result.value);
        }
        assertEquals(0, provider.opened);
    }

    @Test public void arabicUtf8RoundTripIsByteExactAndSaveTruncatesOldFile() throws Exception {
        Files.write(provider.file.toPath(), new byte[8192]);
        byte[] bytes = ("{\"format\":\"ikram-profile-configurations\",\"version\":1,"
                + "\"profiles\":[{\"id\":\"معرّف-١\","
                + "\"name\":\"إكرام — مُتصفِّح العربية 🧭\\nالسطر الثاني\","
                + "\"proxy\":\"https://proxy.example:443\",\"proxyNeedsReview\":true}]}")
                .getBytes(StandardCharsets.UTF_8);
        Result saved = start("save", bytes);
        complete(saved);
        assertNull(saved.error);
        assertEquals(true, saved.value);
        assertArrayEquals(bytes, Files.readAllBytes(provider.file.toPath()));
        Result opened = start("open", null);
        complete(opened);
        assertNull(opened.error);
        assertArrayEquals(bytes, (byte[]) opened.value);
    }

    @Test public void unavailableProviderFailsBothOperationsAndAllowsRetry() throws Exception {
        provider.unavailable = true;
        for (String method : new String[]{"save", "open"}) {
            Result result = start(method, method.equals("save") ? new byte[]{1} : null);
            complete(result);
            assertEquals("storage_error", result.error);
            assertNull(result.value);
        }
        provider.unavailable = false;
        Result retry = start("save", new byte[]{2});
        complete(retry);
        assertEquals(true, retry.value);
    }

    @Test public void unwritableStorageNeverReportsSaved() throws Exception {
        provider.readOnly = true;
        Result result = start("save", new byte[]{1, 2, 3});
        complete(result);
        assertEquals("storage_error", result.error);
        assertNull(result.value);
    }

    @Test public void missingDocumentUriIsNotCancellationOrSuccess() {
        Result result = start("open", null);
        plugin.onActivityResult(ProfileBackupDocumentsPlugin.REQUEST, Activity.RESULT_OK, new Intent());
        assertEquals("unavailable", result.error);
        assertEquals(1, result.completions);
    }

    @Test public void missingSystemPickerReportsUnavailableWithoutProviderIO() {
        plugin.onDetachedFromActivity();
        attach(Robolectric.buildActivity(NoDocumentsActivity.class).setup().get());
        Result result = start("open", null);
        assertEquals("unavailable", result.error);
        assertEquals(1, result.completions);
        assertEquals(0, provider.opened);
    }

    @Test public void oversizedProviderStreamFailsBeforeReturningBytes() throws Exception {
        Files.write(provider.file.toPath(), new byte[ProfileBackupDocumentsPlugin.MAX_BYTES + 1]);
        Result result = start("open", null);
        complete(result);
        assertEquals("too_large", result.error);
        assertNull(result.value);
    }

    @Test public void pendingOperationSurvivesActivityRecreationAndRejectsDoubleOpen() {
        Result first = start("open", null);
        Result second = start("open", null);
        assertEquals("busy", second.error);
        plugin.onDetachedFromActivityForConfigChanges();
        attach(Robolectric.buildActivity(Activity.class).setup().get());
        plugin.onActivityResult(ProfileBackupDocumentsPlugin.REQUEST, Activity.RESULT_CANCELED, null);
        assertEquals(1, first.completions);
        assertNull(first.error);
    }

    @Test public void activityLossCompletesPendingRequestOnlyOnce() {
        Result result = start("open", null);
        plugin.onDetachedFromActivity();
        assertEquals("unavailable", result.error);
        assertFalse(plugin.onActivityResult(ProfileBackupDocumentsPlugin.REQUEST,
                Activity.RESULT_CANCELED, null));
        assertEquals(1, result.completions);
    }

    @Test public void boundedReadAcceptsLimitAndRejectsOneExtraByte() throws Exception {
        assertArrayEquals(new byte[]{1, 2},
                ProfileBackupDocumentsPlugin.readBounded(new ByteArrayInputStream(new byte[]{1, 2}), 2));
        try {
            ProfileBackupDocumentsPlugin.readBounded(new ByteArrayInputStream(new byte[]{1, 2, 3}), 2);
            fail("Oversized stream must fail");
        } catch (ProfileBackupDocumentsPlugin.TooLargeException expected) {
            // The native read cap is enforced even if provider size metadata lies.
        }
    }
}
