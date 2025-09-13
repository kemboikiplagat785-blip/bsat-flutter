To create Android build version,

``` 
  flutter build apk --obfuscate --split-debug-info=debug_symbols
  firebase crashlytics:symbols:upload --app=1:488060923998:android:52eae0d7dce7b5aed144cf debug_symbols
  flutter build apk --obfuscate --split-debug-info=debug_symbols
```
