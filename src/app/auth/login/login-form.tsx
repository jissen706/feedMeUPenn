"use client";

import { useEffect, useState } from "react";
import { z } from "zod";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/hooks/use-toast";

const emailSchema = z
  .string()
  .email("Enter a valid email")
  .regex(/@upenn\.edu$/i, "Use your @upenn.edu email");

export function LoginForm() {
  const supabase = createClient();
  const { toast } = useToast();
  const [email, setEmail] = useState("");
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const err = params.get("error");
    if (!err) return;
    const description =
      err === "missing_code"
        ? "The link was incomplete. Send yourself a new one."
        : err === "session"
          ? "That sign-in link is no longer valid. Try again."
          : "Something went wrong. Try sending a new link.";
    toast({ title: "Sign-in failed", description, variant: "destructive" });
    window.history.replaceState(null, "", "/auth/login");
  }, [toast]);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    const value = email.trim().toLowerCase();
    const parsed = emailSchema.safeParse(value);
    if (!parsed.success) {
      toast({
        title: "Penn email required",
        description:
          parsed.error.issues[0]?.message ?? "Use your @upenn.edu address.",
        variant: "destructive",
      });
      return;
    }
    setSending(true);
    const { error } = await supabase.auth.signInWithOtp({
      email: parsed.data,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
      },
    });
    setSending(false);
    if (error) {
      toast({
        title: "Couldn't send link",
        description: error.message,
        variant: "destructive",
      });
      return;
    }
    setSent(true);
  }

  if (sent) {
    return (
      <div className="space-y-6 text-center">
        <div className="space-y-2">
          <h1 className="text-2xl font-semibold tracking-tight">Check your email</h1>
          <p className="text-base text-muted-foreground">
            We sent a sign-in link to{" "}
            <span className="font-medium text-foreground">{email}</span>. Tap it
            from your phone to continue.
          </p>
        </div>
        <Button
          variant="ghost"
          className="h-12 w-full rounded-xl font-medium"
          onClick={() => {
            setSent(false);
            setEmail("");
          }}
        >
          Use a different email
        </Button>
      </div>
    );
  }

  return (
    <form onSubmit={onSubmit} className="space-y-6">
      <div className="space-y-2 text-center">
        <h1 className="text-2xl font-semibold tracking-tight">Sign in to Swipey</h1>
        <p className="text-base text-muted-foreground">
          We&rsquo;ll email you a link. No password.
        </p>
      </div>
      <div className="space-y-2">
        <label htmlFor="email" className="sr-only">
          Penn email
        </label>
        <Input
          id="email"
          type="email"
          inputMode="email"
          autoComplete="email"
          autoCapitalize="off"
          autoCorrect="off"
          placeholder="you@upenn.edu"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          disabled={sending}
          required
          className="h-12 rounded-xl text-base"
        />
      </div>
      <Button
        type="submit"
        disabled={sending || email.length === 0}
        className="h-12 w-full rounded-xl font-medium"
      >
        {sending ? "Sending..." : "Send magic link"}
      </Button>
    </form>
  );
}
