"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { z } from "zod";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/hooks/use-toast";

const schema = z.object({
  first_name: z
    .string()
    .trim()
    .min(1, "First name is required")
    .max(50, "Too long")
    .regex(/^[A-Za-z\s-]+$/, "Letters, spaces, and hyphens only"),
  phone: z.string().optional(),
});

type FormValues = z.infer<typeof schema>;

export function OnboardingForm() {
  const supabase = createClient();
  const router = useRouter();
  const { toast } = useToast();
  const [submitting, setSubmitting] = useState(false);

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { first_name: "", phone: "" },
  });

  async function onSubmit(values: FormValues) {
    setSubmitting(true);
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      router.replace("/auth/login");
      return;
    }
    const phoneDigits = values.phone?.replace(/\D/g, "") || null;
    const { error } = await supabase
      .from("profiles")
      .update({
        first_name: values.first_name,
        phone: phoneDigits,
      })
      .eq("id", user.id);
    setSubmitting(false);
    if (error) {
      toast({
        title: "Couldn't save",
        description: error.message,
        variant: "destructive",
      });
      return;
    }
    router.replace("/");
    router.refresh();
  }

  const errors = form.formState.errors;

  return (
    <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
      <div className="space-y-2 text-center">
        <h1 className="text-2xl font-semibold tracking-tight">Welcome to Swipey</h1>
        <p className="text-base text-muted-foreground">
          Tell us a bit so people know who they&rsquo;re meeting at pickup.
        </p>
      </div>

      <div className="space-y-2">
        <label htmlFor="first_name" className="text-sm font-medium">
          First name
        </label>
        <Input
          id="first_name"
          autoComplete="given-name"
          placeholder="Alex"
          disabled={submitting}
          className="h-12 rounded-xl text-base"
          {...form.register("first_name")}
        />
        {errors.first_name && (
          <p className="text-sm text-red-500">{errors.first_name.message}</p>
        )}
      </div>

      <div className="space-y-2">
        <label htmlFor="phone" className="text-sm font-medium">
          Phone
        </label>
        <Input
          id="phone"
          type="tel"
          inputMode="tel"
          autoComplete="tel"
          placeholder="(215) 555-0123"
          disabled={submitting}
          className="h-12 rounded-xl text-base"
          {...form.register("phone")}
        />
        <p className="text-sm text-muted-foreground">
          Optional but recommended &mdash; donors and eaters need this to
          coordinate pickup.
        </p>
        {errors.phone && (
          <p className="text-sm text-red-500">{errors.phone.message}</p>
        )}
      </div>

      <Button
        type="submit"
        disabled={submitting}
        className="h-12 w-full rounded-xl font-medium"
      >
        {submitting ? "Saving..." : "Continue"}
      </Button>
    </form>
  );
}
