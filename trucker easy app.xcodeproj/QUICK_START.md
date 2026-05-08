# QUICK START GUIDE

## Get Trucker Easy Running in 30 Minutes

### Prerequisites
- macOS Sonoma 14.0+
- Xcode 15.0+
- iOS 17.0+ device or simulator
- Active Apple Developer account

---

## Step 1: Clone & Open (5 minutes)

```bash
# Create project directory
mkdir TruckerEasy
cd TruckerEasy

# Copy all provided Swift files into project
# Open in Xcode
open TruckerEasy.xcodeproj
```

---

## Step 2: Quick API Setup (10 minutes)

### Option A: Use Mock Data (Fastest - for UI testing)

Create `Config.swift`:
```swift
enum Config {
    static let useMockData = true
    static let supabaseURL = "https://mock.supabase.co"
    static let supabaseKey = "mock_key"
    static let hereAPIKey = "mock_key"
    static let newsAPIKey = "mock_key"
}
```

### Option B: Real APIs (Recommended for full testing)

1. **Supabase** (5 min)
   - Sign up at [supabase.com](https://supabase.com)
   - Create project
   - Copy URL and anon key from Settings > API

2. **HERE Maps** (3 min)
   - Sign up at [developer.here.com](https://developer.here.com)
   - Create project
   - Generate API key (Freemium tier = free for testing)

3. **NewsAPI** (2 min)
   - Get key at [newsapi.org](https://newsapi.org)
   - Free tier: 100 requests/day

Create `Config.xcconfig`:
```
SUPABASE_URL = your_url_here
SUPABASE_ANON_KEY = your_key_here
HERE_API_KEY = your_key_here
NEWSAPI_KEY = your_key_here
```

---

## Step 3: Install Dependencies (5 minutes)

In Xcode:
1. File > Add Package Dependencies
2. Add:
   ```
   https://github.com/supabase/supabase-swift
   ```
3. Click "Add Package"

---

## Step 4: Configure Permissions (3 minutes)

Edit `Info.plist`:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location for truck navigation</string>

<key>NSCameraUsageDescription</key>
<string>Scan documents for your digital vault</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Upload document photos</string>

<key>NSMicrophoneUsageDescription</key>
<string>Voice chat with Easy assistant</string>
```

---

## Step 5: Build & Run (2 minutes)

1. Select iPhone 15 Pro simulator
2. Press ⌘ + R
3. Wait for app to launch

---

## Step 6: Test Key Features (5 minutes)

### Test 1: Checkout Flow
1. App launches to checkout page
2. Tap "Start Free Trial"
3. You should see main tab view

### Test 2: Map Navigation
1. Go to "My Horizon" tab
2. Tap "Got Load?"
3. Paste this test address:
   ```
   123 Main Street, Columbus, OH 43215
   ```
4. Tap "Start Navigation"
5. Map should show route

### Test 3: Health Check-in
1. Go to "My Check-up" tab
2. Tap 4 stars for mood
3. See message: "Good day on the road!"

### Test 4: Add Document
1. Go to "My Cabin" tab
2. Tap "Add CDL"
3. Set expiration date (future)
4. Choose photo
5. Save document

### Test 5: AI Chat
1. Go to "Road Talk" tab
2. Tap "Chat with Easy"
3. Type: "Hello"
4. See AI response

---

## Troubleshooting

### Build Errors

**Error**: Cannot find 'Supabase' in scope
- Solution: File > Packages > Resolve Package Versions

**Error**: No such module 'MapKit'
- Solution: Add `import MapKit` to file

**Error**: API key not found
- Solution: Check Config.xcconfig is in target membership

### Runtime Issues

**Map not showing**:
- Enable Location Services in simulator
- Settings > Privacy > Location Services > TruckerEasy > While Using

**Camera not working in simulator**:
- Use "Choose Photo" instead of "Take Photo"
- Simulator doesn't have camera

**Notifications not appearing**:
- Settings > Notifications > TruckerEasy > Allow Notifications

---

## Mock Data for Testing

### Address Extraction Test Cases

Paste these into "Got Load?" to test regex:

```
Case 1 (Full Address):
Pick up at 123 Main Street, Columbus, OH 43215
Contact: John (555-1234)

Case 2 (Minimal):
456 Industrial Blvd, Dallas, TX 75201

Case 3 (Multiple Addresses):
Origin: 789 Oak Ave, Miami, FL 33101
Destination: 321 Pine Road, Atlanta, GA 30303

Case 4 (With Special Characters):
Load #12345 | 555 Commerce Dr., Suite 200, Chicago, IL 60601

Case 5 (No Address - Should fail gracefully):
Call dispatcher for details. Weight: 45,000 lbs.
```

Expected: App extracts first valid address, shows in green box.

---

## Sample Data Seeds

### Test User Profile
```swift
let testProfile = UserProfile(
    id: "test-user-123",
    name: "Test Driver",
    healthConditions: [.diabetic],
    allergies: ["Peanuts"],
    dietaryPreferences: .lowSodium
)
```

### Test Documents
```swift
let testDocuments = [
    Document(type: .cdl, expirationDate: Date().addingTimeInterval(365*24*60*60)), // 1 year
    Document(type: .medicalCard, expirationDate: Date().addingTimeInterval(30*24*60*60)), // 30 days (yellow)
    Document(type: .dotPhysical, expirationDate: Date().addingTimeInterval(-1*24*60*60)) // Expired (red)
]
```

### Test Medications
```swift
let testMeds = [
    Medication(name: "Blood Pressure", time: Date().addingTimeInterval(3600), repeatDaily: true),
    Medication(name: "Diabetes Med", time: Date().addingTimeInterval(7200), repeatDaily: true)
]
```

---

## Development Tips

### Hot Reload with SwiftUI Previews

Use `#Preview` for instant UI updates:
```swift
#Preview {
    MyHorizonView()
        .environmentObject(LocationManager())
}
```

### Debug Print Statements
```swift
print("🗺️ Route calculated: \(route.destinationName)")
print("💊 Medication reminder triggered")
print("📄 Document uploaded to: \(imageURL)")
```

### Xcode Console Filters
- `🗺️` - Map/Navigation
- `💊` - Health/Medications
- `📄` - Documents
- `💬` - AI Chat
- `💰` - Purchases

---

## Performance Testing

### Memory Usage
```swift
// Add to each ViewModel
deinit {
    print("♻️ \(Self.self) deallocated")
}
```

### Network Monitoring
Enable in Xcode:
1. Product > Scheme > Edit Scheme
2. Run > Arguments > Environment Variables
3. Add: `CFNETWORK_DIAGNOSTICS` = `3`

### Time Profiling
```swift
let start = Date()
let address = viewModel.extractAddress(from: text)
let duration = Date().timeIntervalSince(start)
print("⏱️ Address extraction took \(duration * 1000)ms")
```

---

## UI Testing Checklist

### One-Hand Operation Test
1. Hold iPhone in left hand only
2. Try to:
   - [ ] Dismiss map alert with thumb
   - [ ] Tap "Got Load?" button
   - [ ] Rate mood stars
   - [ ] Open medication card
   - [ ] Scroll documents list

### Accessibility Test
1. Enable VoiceOver: Settings > Accessibility > VoiceOver
2. Navigate entire app with swipes
3. Verify all buttons are labeled
4. Check contrast in Accessibility Inspector

### Dark Mode Test
1. Enable: Settings > Display > Dark
2. Check all screens
3. Verify colors have sufficient contrast

---

## Deployment Checklist

### Pre-Production
- [ ] Change `useMockData` to `false`
- [ ] Add real API keys
- [ ] Test on physical device
- [ ] Run all unit tests (⌘ + U)
- [ ] Profile memory leaks (Instruments)
- [ ] Test offline mode

### Production Build
```bash
# Bump version
# In Xcode: Target > General > Version
# Example: 1.0 (1) → 1.0 (2)

# Archive for App Store
# Product > Archive
# Distribute App > App Store Connect
```

---

## Common Workflows

### Adding a New Feature

1. **Create View**
```swift
struct NewFeatureView: View {
    var body: some View {
        Text("New Feature")
    }
}
```

2. **Create ViewModel**
```swift
@MainActor
class NewFeatureViewModel: ObservableObject {
    @Published var data: [Item] = []
}
```

3. **Add to Navigation**
```swift
// In MainTabView.swift
NewFeatureView()
    .tabItem {
        Label("Feature", systemImage: "star.fill")
    }
    .tag(4)
```

### Debugging Map Issues

```swift
// In MyHorizonView
.onAppear {
    print("🗺️ Current location: \(locationManager.currentLocation)")
    print("🗺️ Authorization: \(locationManager.authorizationStatus)")
}
```

### Testing Notifications Locally

```swift
// Trigger notification in 5 seconds
let content = UNMutableNotificationContent()
content.title = "Test Notification"
content.body = "This is a test"

let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

UNUserNotificationCenter.current().add(request)
print("⏰ Notification scheduled for 5 seconds from now")
```

---

## Resources

### Learning SwiftUI
- [100 Days of SwiftUI](https://www.hackingwithswift.com/100/swiftui)
- [Apple's SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)
- [SwiftUI by Example](https://www.hackingwithswift.com/quick-start/swiftui)

### MapKit
- [Apple MapKit Documentation](https://developer.apple.com/documentation/mapkit)
- [MapKit Tutorial](https://www.raywenderlich.com/7738344-mapkit-tutorial-getting-started)

### Supabase Swift
- [Supabase Swift GitHub](https://github.com/supabase/supabase-swift)
- [Supabase Docs](https://supabase.com/docs)

---

## Support

Need help? Check:
1. `README.md` - Overview and features
2. `DESIGN_GUIDE.md` - UI/UX specifications
3. `SUPABASE_SETUP.md` - Backend configuration
4. `IMPLEMENTATION_CHECKLIST.md` - Step-by-step tasks

---

**You're all set! Time to build the best trucker app in the App Store. 🚛💨**

**Remember**: This is built by drivers, for drivers. Every decision should ask: "Would this make a driver's life easier?"

Good luck, and safe travels! 🛣️
