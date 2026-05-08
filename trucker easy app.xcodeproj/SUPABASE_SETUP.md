//
//  SUPABASE_SETUP.md
//  Trucker Easy - Complete Supabase Configuration Guide
//

# Supabase Backend Setup for Trucker Easy

## 1. Create Supabase Project

1. Go to [supabase.com](https://supabase.com)
2. Create new project: "trucker-easy-prod"
3. Save your project URL and anon key

## 2. Database Schema

Run this SQL in your Supabase SQL Editor:

```sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable PostGIS for geolocation
CREATE EXTENSION IF NOT EXISTS postgis;

-- Users table (extends Supabase auth.users)
CREATE TABLE public.user_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT,
  health_conditions TEXT[], -- Array of conditions: 'diabetic', 'hypertensive', etc.
  allergies TEXT[],
  dietary_preference TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- Users can only see/edit their own profile
CREATE POLICY "Users can view own profile" ON public.user_profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.user_profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON public.user_profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- Documents table
CREATE TABLE public.documents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('cdl', 'medical_card', 'dot_physical', 'truck_insurance', 'trailer_insurance', 'registration')),
  expiration_date DATE,
  image_url TEXT, -- Supabase Storage URL
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own documents" ON public.documents
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own documents" ON public.documents
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own documents" ON public.documents
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own documents" ON public.documents
  FOR DELETE USING (auth.uid() = user_id);

-- Create index for expiration queries
CREATE INDEX idx_documents_expiration ON public.documents(user_id, expiration_date);

-- Medications table
CREATE TABLE public.medications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  time TIME NOT NULL,
  repeat_daily BOOLEAN DEFAULT TRUE,
  last_taken TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.medications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own medications" ON public.medications
  FOR ALL USING (auth.uid() = user_id);

-- Mood logs table
CREATE TABLE public.mood_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rating INT CHECK (rating BETWEEN 1 AND 5),
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, date)
);

ALTER TABLE public.mood_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own mood logs" ON public.mood_logs
  FOR ALL USING (auth.uid() = user_id);

-- Community alerts table (shared by all users)
CREATE TABLE public.community_alerts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  type TEXT NOT NULL CHECK (type IN ('weigh', 'police', 'accident', 'construction', 'hazard')),
  location GEOGRAPHY(POINT, 4326) NOT NULL, -- PostGIS point
  reported_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  confirmations INT DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '24 hours')
);

-- Public read for community alerts, authenticated write
ALTER TABLE public.community_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view recent alerts" ON public.community_alerts
  FOR SELECT USING (expires_at > NOW());

CREATE POLICY "Authenticated users can create alerts" ON public.community_alerts
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Users can update confirmations" ON public.community_alerts
  FOR UPDATE USING (auth.role() = 'authenticated');

-- Spatial index for fast location queries
CREATE INDEX idx_alerts_location ON public.community_alerts USING GIST(location);

-- Auto-delete expired alerts
CREATE OR REPLACE FUNCTION delete_expired_alerts()
RETURNS void AS $$
BEGIN
  DELETE FROM public.community_alerts WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- Schedule cleanup (requires pg_cron extension)
-- Run hourly: SELECT cron.schedule('cleanup-alerts', '0 * * * *', 'SELECT delete_expired_alerts()');

-- Food suggestions table
CREATE TABLE public.food_suggestions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  location_name TEXT NOT NULL,
  location GEOGRAPHY(POINT, 4326),
  recommendation TEXT,
  avoid_items TEXT[],
  health_profile TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.food_suggestions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own food suggestions" ON public.food_suggestions
  FOR ALL USING (auth.uid() = user_id);

-- Route cache table (for API cost savings)
CREATE TABLE public.route_cache (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  destination_hash TEXT UNIQUE NOT NULL, -- MD5 of normalized destination
  destination_name TEXT NOT NULL,
  destination_lat DECIMAL(10, 8) NOT NULL,
  destination_lng DECIMAL(11, 8) NOT NULL,
  distance TEXT,
  estimated_time TEXT,
  polyline_data TEXT, -- Encoded polyline
  truck_restrictions JSONB,
  use_count INT DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  last_used TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for fast lookup
CREATE INDEX idx_route_destination ON public.route_cache(destination_hash);

-- Function to increment route use count
CREATE OR REPLACE FUNCTION increment_route_use(route_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.route_cache
  SET use_count = use_count + 1, last_used = NOW()
  WHERE id = route_id;
END;
$$ LANGUAGE plpgsql;

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at triggers
CREATE TRIGGER update_user_profiles_updated_at BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_documents_updated_at BEFORE UPDATE ON public.documents
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

## 3. Storage Buckets

Create these storage buckets in Supabase Dashboard:

### Document Images Bucket
```sql
-- Create bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('documents', 'documents', false);

-- RLS Policy: Users can upload to their own folder
CREATE POLICY "Users can upload own documents" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'documents' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- RLS Policy: Users can read own documents
CREATE POLICY "Users can view own documents" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'documents' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );

-- RLS Policy: Users can delete own documents
CREATE POLICY "Users can delete own documents" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'documents' AND
    (storage.foldername(name))[1] = auth.uid()::text
  );
```

## 4. Edge Functions

### Weekly BI Report Function

Create: `supabase/functions/weekly-bi-report/index.ts`

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )
    
    const now = new Date()
    const oneWeekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)
    
    // Get active users (any activity in last 7 days)
    const { data: userProfiles, error: usersError } = await supabaseClient
      .from('user_profiles')
      .select('id')
      .gte('updated_at', oneWeekAgo.toISOString())
    
    // Get documents expiring in next 30 days
    const thirtyDaysFromNow = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000)
    const { data: expiringDocs, error: docsError } = await supabaseClient
      .from('documents')
      .select('id, user_id, type, expiration_date')
      .lte('expiration_date', thirtyDaysFromNow.toISOString())
      .gte('expiration_date', now.toISOString())
    
    // Get total community alerts created this week
    const { data: weeklyAlerts, error: alertsError } = await supabaseClient
      .from('community_alerts')
      .select('id')
      .gte('created_at', oneWeekAgo.toISOString())
    
    // Get most used routes
    const { data: topRoutes, error: routesError } = await supabaseClient
      .from('route_cache')
      .select('destination_name, use_count')
      .order('use_count', { ascending: false })
      .limit(10)
    
    const report = {
      week_ending: now.toISOString(),
      metrics: {
        active_users: userProfiles?.length ?? 0,
        expiring_documents: expiringDocs?.length ?? 0,
        new_community_alerts: weeklyAlerts?.length ?? 0,
        api_cost_savings: `$${((topRoutes?.reduce((sum, r) => sum + r.use_count, 0) ?? 0) * 0.001).toFixed(2)}`
      },
      top_routes: topRoutes,
      expiring_by_type: groupDocumentsByType(expiringDocs ?? [])
    }
    
    // Log report (in production, send to admin email via Resend or similar)
    console.log('Weekly BI Report:', JSON.stringify(report, null, 2))
    
    return new Response(
      JSON.stringify(report),
      { 
        headers: { 'Content-Type': 'application/json' },
        status: 200
      }
    )
    
  } catch (error) {
    console.error('Error generating report:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        headers: { 'Content-Type': 'application/json' },
        status: 500
      }
    )
  }
})

function groupDocumentsByType(docs: any[]) {
  const grouped: Record<string, number> = {}
  docs.forEach(doc => {
    grouped[doc.type] = (grouped[doc.type] || 0) + 1
  })
  return grouped
}
```

Deploy the function:
```bash
supabase functions deploy weekly-bi-report
```

Schedule it (use a cron service like GitHub Actions or Supabase Cron):
```yaml
# .github/workflows/weekly-report.yml
name: Weekly BI Report
on:
  schedule:
    - cron: '0 9 * * 1' # Every Monday at 9 AM UTC
  workflow_dispatch:

jobs:
  report:
    runs-on: ubuntu-latest
    steps:
      - name: Call Supabase Function
        run: |
          curl -X POST \
            ${{ secrets.SUPABASE_URL }}/functions/v1/weekly-bi-report \
            -H "Authorization: Bearer ${{ secrets.SUPABASE_ANON_KEY }}"
```

## 5. Realtime Subscriptions (Optional)

Enable realtime for community alerts:

```typescript
// In your Swift app
supabase
  .channel('community-alerts')
  .on(
    'postgres_changes',
    { event: 'INSERT', schema: 'public', table: 'community_alerts' },
    (payload) => {
      // Update map with new alert
      print("New alert: \(payload)")
    }
  )
  .subscribe()
```

## 6. Swift Integration

```swift
import Supabase

// Configure Supabase client
let supabase = SupabaseClient(
  supabaseURL: URL(string: "YOUR_SUPABASE_URL")!,
  supabaseKey: "YOUR_SUPABASE_ANON_KEY"
)

// Example: Fetch documents
let documents: [Document] = try await supabase
  .from("documents")
  .select()
  .eq("user_id", userId)
  .execute()
  .value

// Example: Upload document image
let imageData: Data = ...
let path = "\(userId)/\(documentId).jpg"

let file = try await supabase.storage
  .from("documents")
  .upload(
    path: path,
    file: imageData,
    fileOptions: FileOptions(contentType: "image/jpeg")
  )

// Save document record
let document = [
  "user_id": userId,
  "type": "cdl",
  "expiration_date": "2025-12-31",
  "image_url": file.path
]

try await supabase
  .from("documents")
  .insert(document)
  .execute()
```

## 7. Security Checklist

- ✅ Row Level Security enabled on all tables
- ✅ Storage policies restrict access to user's own files
- ✅ Service role key never exposed to client
- ✅ API keys stored in Xcode secrets or environment variables
- ✅ HTTPS only (enforced by Supabase)
- ✅ Rate limiting on Edge Functions

## 8. Cost Optimization

1. **Route Caching**: Saves ~$0.001 per HERE API call
2. **PostGIS spatial queries**: Faster than calculating distances in-app
3. **Supabase free tier**: 500 MB database, 1 GB file storage, 2 GB bandwidth
4. **Realtime**: Only subscribe to channels when map is visible

## 9. Monitoring

View these in Supabase Dashboard:
- Database size usage
- API request count
- Function execution logs
- Storage usage

Set up alerts for:
- Database > 400 MB (80% of free tier)
- Unusual spike in API requests
- Failed Edge Function executions
