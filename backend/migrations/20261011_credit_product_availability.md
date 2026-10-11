# Credit experience availability rollout

1. Back up PostgreSQL and run the normal migration command before deploying
   Backend and Admin together. The SQL adds `subscription_only` and
   `is_launched` without removing existing fields. Existing companion
   experiences remain subscription-only; calls are marked unlaunched.
2. Admin's enabled flag controls catalog visibility. An enabled but unlaunched
   experience is visible and cannot be purchased. Real-time call products may
   be enabled as previews but cannot be launched until implemented.
3. Deploy App afterwards. New App versions show Coming soon or Subscribe to
   use. Backend rejects unlaunched and unauthorized purchases before charging,
   including requests from older App versions. Old App versions do not display
   the new status labels, but their purchases are still protected.
4. Verify all subscription/launch combinations with subscribed and unsubscribed
   accounts, including a non-exclusive date and its subsequent interaction.

Rollback Backend and Admin images together. The additive columns can stay;
previous versions ignore them and therefore do not enforce these new flags.
Restore the database backup only if configuration rollback is required, after
preserving any necessary writes made since that backup.
