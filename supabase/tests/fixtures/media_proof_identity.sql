-- CI synthetic baseline ONLY; never a shipped migration or hosted bootstrap.
-- The workflow replaces the token with a fresh random identity before start.
CREATE TABLE public.heha_media_proof_identity (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  nonce text NOT NULL CHECK (nonce ~ '^[a-f0-9]{32}$')
);
ALTER TABLE public.heha_media_proof_identity ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.heha_media_proof_identity FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.heha_media_proof_identity TO service_role;
INSERT INTO public.heha_media_proof_identity(nonce) VALUES ('HEHA_MEDIA_PROOF_NONCE');
