# Build Configuration Setup (5-Minute Quick Start)

## 📌 Problem

- `ValhallaServerURL` in `Info.plist` but not inherited by Xcode target
- API tokens like `$(MBXAccessToken)` not resolved during build
- Valhalla routing unavailable (`isAvailable` = false)

## ✅ Solution

### Step 1: Create Secrets File (1 min)

```bash
# Copy template
cp TruckerEasy.secrets.xcconfig.example TruckerEasy.secrets.xcconfig

# Edit with your API keys
nano TruckerEasy.secrets.xcconfig
```

**Minimum required for dev:**

```xcconfig
VALHALLA_SERVER_URL = https://valhalla1.openstreetmap.de
SupabaseAnonKey = your_supabase_key_here
PRODUCT_BUNDLE_IDENTIFIER = com.driverfordriver.truckereasy
```

### Step 2: Configure Xcode (2 min)

**Project → Build Settings → All → Add User-Defined:**

```
VALHALLA_SERVER_URL = $(inherited)
```

**Target → Build Phases → [+] New Run Script Phase:**

```bash
# Include secrets in build
if [ -f "${SRCROOT}/TruckerEasy.secrets.xcconfig" ]; then
    echo "✅ Secrets loaded"
else
    echo "⚠️ TruckerEasy.secrets.xcconfig not found"
fi
```

### Step 3: Verify (2 min)

```bash
# Clean build
xcodebuild clean build \
  -project "trucker easy app.xcodeproj" \
  -scheme "trucker-easy-app" \
  -configuration Debug

# Check for unresolved variables
xcodebuild build -project "trucker easy app.xcodeproj" \
  -scheme "trucker-easy-app" | grep -i '\$(' || echo "✅ No unresolved variables"
```

### Step 4: Test (1 min)

```bash
# Run tests
xcodebuild test \
  -only-testing "trucker_easy_appTests/BuildConfigValidatorTests"
```

Expected output:
```
✅ All required build configurations are valid
✅ Valhalla server URL resolved
✅ Supabase configured
```

---

## 🔍 Debug Checklist

| Check | Command | Expected |
|-------|---------|----------|
| **Secrets exist** | `ls -la TruckerEasy.secrets.xcconfig` | File exists |
| **No placeholders** | `grep '\$(' TruckerEasy.secrets.xcconfig` | No output |
| **Valhalla URL set** | `grep VALHALLA_SERVER_URL TruckerEasy.secrets.xcconfig` | URL printed |
| **Build succeeds** | `xcodebuild build ...` | Build log shows "BUILD SUCCEEDED" |
| **No unresolved vars** | `xcodebuild build ... \| grep '\$('` | No output |
| **Tests pass** | `xcodebuild test ...` | All tests pass ✅ |

---

## 🚨 Common Issues

### Issue: `VALHALLA_SERVER_URL` still shows `$(VALHALLA_SERVER_URL)` in binary

**Solution:**

1. Verify path in Xcode settings:
   ```
   Build Settings → Search Paths → User Header Search Paths
   → Add: $(SRCROOT)
   ```

2. Clean derived data:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/*
   xcodebuild clean build
   ```

### Issue: `SupabaseAnonKey` not found

**Solution:**

Get from Supabase dashboard:
```
Supabase → [Project] → Settings → API
Copy "anon" key → Paste in TruckerEasy.secrets.xcconfig
```

### Issue: Build fails with "cannot read TruckerEasy.secrets.xcconfig"

**Solution:**

File is gitignored (correct!), must create locally:
```bash
cp TruckerEasy.secrets.xcconfig.example TruckerEasy.secrets.xcconfig
```

---

## 📦 Files Involved

```
Project Root
├── TruckerEasy.secrets.xcconfig.example  (✅ in git)
├── TruckerEasy.secrets.xcconfig          (❌ gitignored, local only)
├── trucker easy app.xcodeproj/
│   ├── project.pbxproj
│   └─��� Info.plist  (✅ has ValhallaServerURL = $(VALHALLA_SERVER_URL))
├── trucker easy app/
│   └── Info.plist  (✅ has ValhallaServerURL)
└── Sources/
    └── Services/Routing/
        └── ValhallaRoutingService.swift  (✅ reads from plist)
```

---

## 🎯 Next Steps

1. ✅ Complete this 5-minute setup
2. 🧪 Run tests: `xcodebuild test -only-testing BuildConfigValidatorTests`
3. 🚀 Build app: `xcodebuild build -project "trucker easy app.xcodeproj"`
4. 📝 For production, see [VALHALLA_SETUP.md](./VALHALLA_SETUP.md)

---

## 💡 Tips

- **Keep secrets file local:** Never commit `TruckerEasy.secrets.xcconfig`
- **Use CI secrets:** In GitHub Actions, inject via `${{ secrets.* }}`
- **Validate on startup:** `BuildConfigValidator.validateAll()` prints debug info
- **Check logs:** `Xcode → Console` shows validation warnings/errors

---

**Done!** 🎉 Valhalla routing should now be active.
