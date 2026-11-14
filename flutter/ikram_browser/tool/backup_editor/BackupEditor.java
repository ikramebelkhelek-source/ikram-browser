package com.ikram.backupeditor;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Disposable CI-only second application. Uses real Android clipboard and SAF,
 * not Flutter channels, preference injection, or a fake document provider.
 * Never packaged with the browser. Only synthetic text belongs here.
 */
public class BackupEditor extends Activity {
    private EditText text;
    private TextView status;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        status = new TextView(this);
        status.setText("EDITOR READY");
        layout.addView(status);
        button(layout, "Paste", () -> {
            ClipboardManager clipboard = getSystemService(ClipboardManager.class);
            if (!clipboard.hasPrimaryClip()) throw new IllegalStateException("Empty clipboard");
            text.setText(clipboard.getPrimaryClip().getItemAt(0).coerceToText(this));
            status.setText("PASTED");
        });
        button(layout, "Copy", () -> {
            getSystemService(ClipboardManager.class).setPrimaryClip(
                ClipData.newPlainText("Synthetic configuration", text.getText()));
            status.setText("COPIED");
        });
        button(layout, "Save", () -> {
            Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
            intent.setType("application/json");
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.putExtra(Intent.EXTRA_TITLE, "editor-backup.json");
            startActivityForResult(intent, 1);
        });
        button(layout, "Open", () -> {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.setType("application/json");
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            startActivityForResult(intent, 2);
        });
        text = new EditText(this);
        text.setContentDescription("Editor text");
        text.setGravity(android.view.Gravity.TOP);
        text.setTextDirection(android.view.View.TEXT_DIRECTION_LTR);
        String initial = getIntent().getStringExtra("syntheticBase64");
        if (initial != null) {
            text.setText(new String(android.util.Base64.decode(initial, 0), StandardCharsets.UTF_8));
        }
        layout.addView(text, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(layout);
        getWindow().setSoftInputMode(3); // Keep keyboard hidden until explicitly requested.
    }

    private void button(LinearLayout layout, String label, Runnable action) {
        Button button = new Button(this);
        button.setText(label);
        button.setAllCaps(false);
        button.setOnClickListener(v -> action.run());
        layout.addView(button);
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (result != RESULT_OK) { status.setText("CANCELLED"); return; }
        try {
            if (data == null || data.getData() == null) throw new IllegalStateException("No URI");
            if (request == 1) {
                try (OutputStream out = getContentResolver().openOutputStream(data.getData(), "wt")) {
                    if (out == null) throw new IllegalStateException("No output stream");
                    out.write(text.getText().toString().getBytes(StandardCharsets.UTF_8));
                }
                status.setText("SAVED");
            } else {
                ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                try (InputStream in = getContentResolver().openInputStream(data.getData())) {
                    if (in == null) throw new IllegalStateException("No input stream");
                    byte[] buffer = new byte[8192];
                    int count;
                    while ((count = in.read(buffer)) != -1) {
                        bytes.write(buffer, 0, count);
                        if (bytes.size() > 1048576) throw new IllegalStateException("Too large");
                    }
                }
                text.setText(bytes.toString("UTF-8"));
                status.setText("OPENED");
            }
        } catch (Exception error) {
            status.setText("ERROR: " + error.getClass().getSimpleName());
        }
    }
}
