import { supabase } from "./supabase";
import { validateAccountDeletionReceipt } from "./accountDeletionReceipt";

export const ACCOUNT_DELETION_RPC = "request_my_account_deletion";

export async function requestAccountDeletion(client = supabase) {
  // Deliberately no arguments: the reviewed RPC must derive identity from auth.uid().
  const { data, error } = await client.rpc(ACCOUNT_DELETION_RPC);
  if (error) {
    throw new Error(
      "Account deletion could not be requested in the app. Please use the account-deletion support page so HEHA can complete it."
    );
  }

  const { status, requestId, requestedAt } = validateAccountDeletionReceipt(data);

  return {
    status,
    requestId,
    requestedAt,
    message:
      status === "already_requested"
        ? "Your account deletion request is already pending."
        : "Your account deletion request was submitted. HEHA will remove the account after the request is verified and processed.",
  };
}
