-- SELECT COALESCE(jsonb_agg(r2), '[]'::JSONB)
-- FROM (
SELECT s.id,
  s.trial_id,
  'STEP_STATE_' || s.state as state,
  s.start_time,
  s.end_time,
  s.num_batches,
  s.prior_batches_processed -- (
  --   SELECT row_to_json(r3)
  --   FROM (
  --       SELECT c.id,
  --         c.trial_id,
  --         c.step_id,
  --         c.state,
  --         c.start_time,
  --         c.end_time,
  --         c.uuid,
  --         c.resources,
  --         c.metadata
  --       FROM checkpoints c
  --       WHERE c.trial_id = t.id
  --         AND c.step_id = s.id
  --     ) r3
  -- ) AS checkpoint,
  -- (
  --   SELECT row_to_json(r4)
  --   FROM (
  --       SELECT v.id,
  --         v.trial_id,
  --         v.step_id,
  --         v.state,
  --         v.start_time,
  --         v.end_time,
  --         v.metrics
  --       FROM validations v
  --       WHERE v.trial_id = t.id
  --         AND v.step_id = s.id
  --     ) r4
  -- ) AS validation
FROM steps s
  INNER JOIN trials t ON (
    s.trial_id = t.id
    AND t.id = 18
  )
ORDER BY s.id ASC -- ) r2
