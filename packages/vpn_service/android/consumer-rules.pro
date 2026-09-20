# The JNI function names in libclash.so are derived from the class and native
# method names. Keep them even when the app is minified.
-keepclasseswithmembernames class io.aote.vpnService.ClashCore {
    native <methods>;
}
