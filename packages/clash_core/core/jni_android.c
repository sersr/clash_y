//go:build android

#if defined(__ANDROID__)

#include <jni.h>

const char *clash_jni_get_string(JNIEnv *env, jstring value) {
    if (env == NULL || value == NULL) {
        return NULL;
    }
    return (*env)->GetStringUTFChars(env, value, NULL);
}

void clash_jni_release_string(JNIEnv *env, jstring value, const char *chars) {
    if (env == NULL || value == NULL || chars == NULL) {
        return;
    }
    (*env)->ReleaseStringUTFChars(env, value, chars);
}

jstring clash_jni_new_string(JNIEnv *env, const char *value) {
    if (env == NULL || value == NULL) {
        return NULL;
    }
    return (*env)->NewStringUTF(env, value);
}

#endif
