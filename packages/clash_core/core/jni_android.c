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



static JavaVM *clash_jni_vm = NULL;
static jobject clash_jni_protector = NULL;
static jmethodID clash_jni_protect_method = NULL;

void clash_jni_set_protector(JNIEnv *env, jobject protector) {
    if (env == NULL) {
        return;
    }
    if (clash_jni_protector != NULL) {
        (*env)->DeleteGlobalRef(env, clash_jni_protector);
        clash_jni_protector = NULL;
    }
    clash_jni_protect_method = NULL;
    if (protector == NULL) {
        return;
    }
    if ((*env)->GetJavaVM(env, &clash_jni_vm) != JNI_OK) {
        return;
    }
    clash_jni_protector = (*env)->NewGlobalRef(env, protector);
    if (clash_jni_protector == NULL) {
        return;
    }
    jclass clazz = (*env)->GetObjectClass(env, protector);
    if (clazz == NULL) {
        return;
    }
    clash_jni_protect_method = (*env)->GetMethodID(env, clazz, "protect", "(I)Z");
    (*env)->DeleteLocalRef(env, clazz);
}

void clash_jni_clear_protector(JNIEnv *env) {
    if (env != NULL && clash_jni_protector != NULL) {
        (*env)->DeleteGlobalRef(env, clash_jni_protector);
    }
    clash_jni_protector = NULL;
    clash_jni_protect_method = NULL;
}

int clash_jni_protect(int fd) {
    if (clash_jni_vm == NULL || clash_jni_protector == NULL || clash_jni_protect_method == NULL) {
        return 0;
    }

    JNIEnv *env = NULL;
    int attached = 0;
    jint result = (*clash_jni_vm)->GetEnv(clash_jni_vm, (void **)&env, JNI_VERSION_1_6);
    if (result == JNI_EDETACHED) {
        if ((*clash_jni_vm)->AttachCurrentThread(clash_jni_vm, (JNIEnv **)&env, NULL) != JNI_OK) {
            return 0;
        }
        attached = 1;
    } else if (result != JNI_OK || env == NULL) {
        return 0;
    }

    jboolean accepted = (*env)->CallBooleanMethod(
        env,
        clash_jni_protector,
        clash_jni_protect_method,
        (jint)fd
    );
    if ((*env)->ExceptionCheck(env)) {
        (*env)->ExceptionClear(env);
        accepted = JNI_FALSE;
    }

    if (attached) {
        (*clash_jni_vm)->DetachCurrentThread(clash_jni_vm);
    }
    return accepted == JNI_TRUE ? 1 : 0;
}

#endif
