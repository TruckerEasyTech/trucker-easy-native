import { useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";

type OpsRealtimeTable = "health_checks" | "notifications" | "usage_metrics";

/**
 * Refetch when Supabase Realtime receives INSERT/UPDATE on ops tables.
 * Requires migration `20260519100000_ops_realtime_publication.sql` on the project.
 */
export function useOpsRealtime(tables: OpsRealtimeTable[], onChange: () => void) {
  useEffect(() => {
    const channel = supabase.channel(`ops-${tables.join("-")}`);

    for (const table of tables) {
      channel.on(
        "postgres_changes",
        { event: "*", schema: "public", table },
        () => onChange(),
      );
    }

    channel.subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [tables, onChange]);
}
