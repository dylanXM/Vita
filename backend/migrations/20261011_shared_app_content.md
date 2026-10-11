# Shared App content rollout

1. Back up the database, then run the normal Backend migration command before
   deploying Backend and Admin together. `20261011_shared_app_content.sql` adds
   the `app` scope and copies the iOS onboarding configuration into that scope.
   Original onboarding rows and all campaign IDs/content remain intact.
2. Deploy Backend and Admin. Both iOS and Android clients now receive the shared
   onboarding and campaigns. Existing platform headers remain compatible; an
   App release is not required. Campaign enablement, schedule, minimum version
   and the existing single-campaign selection behavior remain in effect.
3. Verify Admin shows App on both pages, includes both platforms' campaigns,
   and that public App content is identical for iOS and Android headers with the
   same App version.

Rollback: restore the pre-deployment database backup and previous Backend/Admin
images together. Rolling back only the images would ignore shared onboarding
edits and new/edited `app` campaigns. A database restore discards writes since
the backup, so preserve any required post-deployment data before restoring.
