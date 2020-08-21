SELECT t.id AS id,
    t.start_time AS start_time,
    t.end_time AS end_time,
    t.experiment_id AS experiment_id,
    t.hparams AS hparams,
    'STATE_' || t.state AS state
FROM trials t
WHERE t.experiment_id = $1
