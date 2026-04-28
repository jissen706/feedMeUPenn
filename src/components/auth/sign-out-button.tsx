"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";

export function SignOutButton() {
  const router = useRouter();
  const supabase = createClient();
  const [busy, setBusy] = useState(false);

  async function onClick() {
    setBusy(true);
    await supabase.auth.signOut();
    router.replace("/auth/login");
    router.refresh();
  }

  return (
    <Button
      variant="outline"
      onClick={onClick}
      disabled={busy}
      className="h-12 rounded-xl font-medium"
    >
      {busy ? "Signing out..." : "Sign out"}
    </Button>
  );
}
