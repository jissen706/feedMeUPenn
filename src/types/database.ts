// Hand-typed to match supabase/migrations/0001_init.sql.
// To regenerate from the live Supabase project once the migration is
// applied, run:
//   npx supabase gen types typescript --project-id <project-id> > src/types/database.ts
// (Or `npx supabase gen types typescript --linked` after `supabase link`.)

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type DropStatus =
  | "open"
  | "expired"
  | "completed"
  | "cancelled";

export type ClaimStatus =
  | "pending"
  | "donor_confirmed"
  | "eater_confirmed"
  | "completed"
  | "expired"
  | "cancelled";

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          email: string;
          first_name: string | null;
          phone: string | null;
          muted_until: string | null;
          priority_window_start: string | null;
          priority_window_end: string | null;
          priority_set_date: string | null;
          priority_set_at: string | null;
          donor_count: number;
          created_at: string;
        };
        Insert: {
          id: string;
          email: string;
          first_name?: string | null;
          phone?: string | null;
          muted_until?: string | null;
          priority_window_start?: string | null;
          priority_window_end?: string | null;
          priority_set_date?: string | null;
          priority_set_at?: string | null;
          donor_count?: number;
          created_at?: string;
        };
        Update: {
          id?: string;
          email?: string;
          first_name?: string | null;
          phone?: string | null;
          muted_until?: string | null;
          priority_window_start?: string | null;
          priority_window_end?: string | null;
          priority_set_date?: string | null;
          priority_set_at?: string | null;
          donor_count?: number;
          created_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "profiles_id_fkey";
            columns: ["id"];
            referencedRelation: "users";
            referencedColumns: ["id"];
          }
        ];
      };
      dining_locations: {
        Row: {
          id: string;
          name: string;
          is_active: boolean;
          sort_order: number;
        };
        Insert: {
          id?: string;
          name: string;
          is_active?: boolean;
          sort_order?: number;
        };
        Update: {
          id?: string;
          name?: string;
          is_active?: boolean;
          sort_order?: number;
        };
        Relationships: [];
      };
      drops: {
        Row: {
          id: string;
          donor_id: string;
          location_id: string;
          total_slots: number;
          slots_remaining: number;
          status: DropStatus;
          general_notify_at: string;
          general_notified: boolean;
          created_at: string;
          expires_at: string;
        };
        Insert: {
          id?: string;
          donor_id: string;
          location_id: string;
          total_slots: number;
          slots_remaining: number;
          status?: DropStatus;
          general_notify_at: string;
          general_notified?: boolean;
          created_at?: string;
          expires_at: string;
        };
        Update: {
          id?: string;
          donor_id?: string;
          location_id?: string;
          total_slots?: number;
          slots_remaining?: number;
          status?: DropStatus;
          general_notify_at?: string;
          general_notified?: boolean;
          created_at?: string;
          expires_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "drops_donor_id_fkey";
            columns: ["donor_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "drops_location_id_fkey";
            columns: ["location_id"];
            referencedRelation: "dining_locations";
            referencedColumns: ["id"];
          }
        ];
      };
      claims: {
        Row: {
          id: string;
          drop_id: string;
          eater_id: string;
          status: ClaimStatus;
          was_priority: boolean;
          claimed_at: string;
          claim_expires_at: string;
          donor_confirmed_at: string | null;
          eater_confirmed_at: string | null;
          completed_at: string | null;
        };
        Insert: {
          id?: string;
          drop_id: string;
          eater_id: string;
          status?: ClaimStatus;
          was_priority?: boolean;
          claimed_at?: string;
          claim_expires_at: string;
          donor_confirmed_at?: string | null;
          eater_confirmed_at?: string | null;
          completed_at?: string | null;
        };
        Update: {
          id?: string;
          drop_id?: string;
          eater_id?: string;
          status?: ClaimStatus;
          was_priority?: boolean;
          claimed_at?: string;
          claim_expires_at?: string;
          donor_confirmed_at?: string | null;
          eater_confirmed_at?: string | null;
          completed_at?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "claims_drop_id_fkey";
            columns: ["drop_id"];
            referencedRelation: "drops";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "claims_eater_id_fkey";
            columns: ["eater_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          }
        ];
      };
      push_subscriptions: {
        Row: {
          id: string;
          user_id: string;
          endpoint: string;
          p256dh: string;
          auth: string;
          created_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          endpoint: string;
          p256dh: string;
          auth: string;
          created_at?: string;
        };
        Update: {
          id?: string;
          user_id?: string;
          endpoint?: string;
          p256dh?: string;
          auth?: string;
          created_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "push_subscriptions_user_id_fkey";
            columns: ["user_id"];
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          }
        ];
      };
    };
    Views: {
      public_profiles: {
        Row: {
          id: string | null;
          first_name: string | null;
          donor_count: number | null;
        };
        Relationships: [];
      };
    };
    Functions: {
      claim_drop: {
        Args: { p_drop_id: string; p_user_id: string };
        Returns: Database["public"]["Tables"]["claims"]["Row"];
      };
      confirm_claim: {
        Args: { p_claim_id: string; p_user_id: string; p_role: string };
        Returns: Database["public"]["Tables"]["claims"]["Row"];
      };
      cancel_claim: {
        Args: { p_claim_id: string; p_user_id: string };
        Returns: undefined;
      };
      set_priority_window: {
        Args: { p_user_id: string; p_start: string; p_end: string };
        Returns: Database["public"]["Tables"]["profiles"]["Row"];
      };
    };
    Enums: {
      drop_status: DropStatus;
      claim_status: ClaimStatus;
    };
    CompositeTypes: Record<string, never>;
  };
};
