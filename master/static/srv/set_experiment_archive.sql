UPDATE experiments
SET archived = $2
WHERE id = $1
RETURNING id
