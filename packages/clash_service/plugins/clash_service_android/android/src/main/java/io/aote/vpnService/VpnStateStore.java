package io.aote.vpnService;

import android.content.Context;
import android.util.AtomicFile;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;

public final class VpnStateStore {
    private static final String STATE_FILE = "clash_vpn_active";

    private VpnStateStore() {}

    public static boolean isVpnActive(Context context) {
        AtomicFile state = new AtomicFile(new File(context.getFilesDir(), STATE_FILE));
        try {
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(state.openRead(), StandardCharsets.UTF_8))) {
                return "1".equals(reader.readLine());
            }
        } catch (FileNotFoundException ignored) {
            return false;
        } catch (IOException error) {
            throw new IllegalStateException("Failed to read VPN state", error);
        }
    }

    public static void setVpnActive(Context context, boolean active) {
        AtomicFile state = new AtomicFile(new File(context.getFilesDir(), STATE_FILE));
        FileOutputStream output;
        try {
            output = state.startWrite();
        } catch (IOException error) {
            throw new IllegalStateException("Failed to begin VPN state write", error);
        }
        try {
            output.write((active ? "1" : "0").getBytes(StandardCharsets.UTF_8));
            state.finishWrite(output);
        } catch (IOException error) {
            state.failWrite(output);
            throw new IllegalStateException("Failed to write VPN state", error);
        }
    }
}
