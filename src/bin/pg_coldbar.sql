
CREATE FUNCTION pg_coldbar_version() RETURNS text
  IMMUTABLE
  BEGIN ATOMIC
    SELECT extversion version FROM pg_extension WHERE extname='pg_coldbar';
  END;
COMMENT ON FUNCTION pg_coldbar_version() IS 'Get version of the currently installed pg_coldbar extension.';

