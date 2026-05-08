# Trucker Easy - Driver to Driver

🚛 A comprehensive Super App for truck drivers focused on Heavy Load Navigation, Wellness Management, and Document Organization.

## Features

### 🗺️ Tab 1: My Horizon (Navigation)
- **Full 3D Map** with Google Earth-style rendering using MapKit
- **"Got Load?" Quick Action** - Paste load info, auto-extract address with Regex, start route instantly
- **Truck-specific routing** with weight/height restrictions via HERE Maps API
- **Community Alerts** - Real-time warnings for weigh stations, police, accidents
- **Easy-to-tap alert buttons** designed for one-handed use while driving
- **Offline route caching** - Saves frequent routes to reduce API costs

### ❤️ Tab 2: My Check-up (Wellness)
- **Daily mood tracking** with 5-star rating (no typing required)
- **Medication reminders** with simple "Took It" / "Remind Later" alerts
- **Geofencing food suggestions** - Notifies 15 min before rest stops
- **Health-based meal recommendations** for diabetics, hypertensive drivers, allergies, diets

### 📁 Tab 3: My Cabin (Documents)
- **Digital vault** for CDL, Medical Card, DOT Physical, Insurance docs
- **Traffic light status system**:
  - 🟢 Green = Valid
  - 🟡 Yellow = Expiring in 30 days
  - 🔴 Red = Expired
- **Photo upload** via camera or gallery
- **Expiration tracking** with smart alerts

### 💬 Tab 4: Road Talk (Community)
- **Auto news feed** via NewsAPI - Latest trucking & logistics news
- **AI Chat "Easy"** - Voice or text assistant for app help & DOT regulations
- **Driver-to-Driver tone** - Friendly, helpful, non-corporate

## Sales Page (Checkout)

### Pricing
- **Monthly**: $19.99/month
- **Annual**: $169.90/year (Save $69.98!)
- **3-Day Free Trial** - No commitment, cancel anytime

### Trust Elements
- ✅ Powered by Driver for Driver
- ✅ Secure & Private
- ✅ 5-Star Rated
- ✅ Built by actual truck drivers

### High-Contrast CTA
The "Start Free Trial" button uses a bold orange gradient with shadow for maximum visibility (more eye-catching than competitors).

## Technical Stack

### Frontend
- **SwiftUI** for native iOS experience
- **MapKit** with 3D elevation rendering
- **StoreKit 2** for subscriptions
- **Speech Framework** for voice input
- **UserNotifications** for medication & geofence alerts

### Backend
- **Supabase** (PostgreSQL database)
  - User authentication
  - Document storage
  - Community alerts
  - Health logs
  - Mood tracking

### APIs
- **HERE Maps API** - Truck routing with weight/height restrictions
- **NewsAPI** - Trucking news feed
- **Foundation Models** (Apple) or OpenAI - AI chat assistant

### Edge Functions (Supabase)
Weekly Business Intelligence reports:
- Active users count
- Documents expiring soon
- Most used routes
- Community alert trends

## Key UX Decisions

### 1. One-Hand Safety
All critical actions (dismiss alerts, confirm alerts) have large 50x50pt touch targets for easy thumb access while driving.

### 2. Offline Resilience
Routes are cached locally. If internet drops during navigation, the route continues without interruption.

### 3. API Cost Optimization
Frequent routes are cached locally, so if a driver runs the same route daily, HERE API is only called once.

### 4. Privacy First
- All documents encrypted
- Location data never sold
- Health data stays local or encrypted in Supabase

## Setup Instructions

### 1. Prerequisites
```bash
# Install Xcode 15.0+
# iOS 17.0+ deployment target
```

### 2. API Keys Required
```swift
// Add to Config.xcconfig or Environment Variables:

SUPABASE_URL=your_supabase_project_url
SUPABASE_ANON_KEY=your_supabase_anon_key
HERE_API_KEY=your_here_maps_api_key
NEWSAPI_KEY=your_newsapi_key
```

### 3. Supabase Schema

```sql
-- Users table
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Documents table
CREATE TABLE documents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  expiration_date DATE,
  image_url TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Medications table
CREATE TABLE medications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  time TIME NOT NULL,
  repeat_daily BOOLEAN DEFAULT TRUE,
  last_taken TIMESTAMP
);

-- Mood logs table
CREATE TABLE mood_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  rating INT CHECK (rating BETWEEN 1 AND 5),
  date DATE NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, date)
);

-- Community alerts table
CREATE TABLE community_alerts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  type TEXT NOT NULL,
  latitude DECIMAL(10, 8) NOT NULL,
  longitude DECIMAL(11, 8) NOT NULL,
  reported_by UUID REFERENCES users(id),
  confirmations INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Create index for geospatial queries
CREATE INDEX idx_alerts_location ON community_alerts USING gist (
  ll_to_earth(latitude, longitude)
);

-- Food suggestions table
CREATE TABLE food_suggestions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  location_name TEXT NOT NULL,
  latitude DECIMAL(10, 8),
  longitude DECIMAL(11, 8),
  recommendation TEXT,
  health_profile TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);
```

### 4. Edge Function Example (weekly-bi-report)

```typescript
// supabase/functions/weekly-bi-report/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )
  
  // Get active users (logged in last 7 days)
  const { data: activeUsers } = await supabase
    .from('users')
    .select('id')
    .gte('last_login', new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString())
  
  // Get expiring documents
  const { data: expiringDocs } = await supabase
    .from('documents')
    .select('*')
    .lte('expiration_date', new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString())
    .gte('expiration_date', new Date().toISOString())
  
  // Send email to admin
  const report = {
    activeUsers: activeUsers?.length ?? 0,
    expiringDocuments: expiringDocs?.length ?? 0,
    timestamp: new Date().toISOString()
  }
  
  console.log('Weekly BI Report:', report)
  
  return new Response(JSON.stringify(report), {
    headers: { 'Content-Type': 'application/json' }
  })
})
```

### 5. Permissions Required (Info.plist)

```xml
<!-- Location Services -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Trucker Easy needs your location for truck navigation and community alerts.</string>

<key>NSLocationAlwaysUsageDescription</key>
<string>Trucker Easy uses your location to notify you of nearby rest stops for meal suggestions.</string>

<!-- Camera for document scanning -->
<key>NSCameraUsageDescription</key>
<string>Trucker Easy needs camera access to scan and store your documents.</string>

<!-- Photo Library -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Trucker Easy needs photo access to upload document images.</string>

<!-- Microphone for voice chat -->
<key>NSMicrophoneUsageDescription</key>
<string>Trucker Easy needs microphone access for voice commands with Easy.</string>

<!-- Speech Recognition -->
<key>NSSpeechRecognitionUsageDescription</key>
<string>Trucker Easy uses speech recognition to transcribe your voice messages.</string>

<!-- Notifications -->
<key>NSUserNotificationsUsageDescription</key>
<string>Trucker Easy sends medication reminders and meal suggestions.</string>
```

## Design Guidelines

### Typography
- Headlines: SF Pro Display Bold
- Body: SF Pro Text Regular
- Buttons: SF Pro Text Semibold

### Spacing
- Large spacing: 24pt (between major sections)
- Medium: 16pt (between cards)
- Small: 8pt (within components)

### Accessibility
- Minimum touch target: 44x44pt (alerts use 50x50pt for safety)
- VoiceOver support for all actions
- Dynamic Type support
- High contrast mode compatible

## Deployment

### App Store Submission
1. Create App Store Connect listing
2. Screenshots for all tab features
3. Emphasize "Driver to Driver" messaging
4. Highlight 3-day free trial
5. Categories: Navigation, Health & Fitness
6. Age Rating: 4+

### Marketing Copy
**Tagline**: "Built by a driver, for drivers."

**Description**:
"Trucker Easy is your complete road companion. Get truck-specific navigation with real-time community alerts, track your wellness with medication reminders and meal suggestions, organize all your CDL and DOT documents in one secure vault, and chat with Easy, your AI assistant who speaks driver. Because the best apps come from people who live the life. Driver to Driver. 🚛"

## Roadmap

### Version 1.1
- [ ] Weather overlays on map
- [ ] Fuel price tracking
- [ ] Load board integration
- [ ] Sleep tracking & HOS compliance

### Version 2.0
- [ ] Social features (driver profiles, convoy mode)
- [ ] Gamification (safe driving rewards)
- [ ] Apple Watch companion app
- [ ] CarPlay integration

## Support

For drivers, by drivers. Email: support@truckereasy.com

## License

Proprietary - © 2026 Trucker Easy LLC
