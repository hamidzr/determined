package command

import (
	"time"

	"github.com/determined-ai/determined/master/internal/scheduler"
	"github.com/determined-ai/determined/master/pkg/container"
	"github.com/determined-ai/determined/master/pkg/model"
)

type (
	// GetSummary is an actor message for getting the summary of the command.
	GetSummary struct {
		userFilter string
	}
)

type (
	// Summary holds an immutable snapshot of the command.
	Summary struct {
		RegisteredTime time.Time              `json:"registered_time"`
		Owner          commandOwner           `json:"owner"`
		ID             scheduler.TaskID       `json:"id"`
		Config         model.CommandConfig    `json:"config"`
		State          string                 `json:"state"`
		ServiceAddress *string                `json:"service_address"`
		Addresses      []scheduler.Address    `json:"addresses"`
		ExitStatus     *string                `json:"exit_status"`
		Misc           map[string]interface{} `json:"misc"`
		IsReady        bool                   `json:"is_ready"`
		AgentUserGroup *model.AgentUserGroup  `json:"agent_user_group"`
	}
)

// newSummary returns a new summary of the command.
func newSummary(c *command) Summary {
	state := "PENDING"
	switch {
	case c.container != nil:
		state = c.container.State.String()
	case c.exitStatus != nil:
		state = container.Terminated.String()
	}
	return Summary{
		RegisteredTime: c.registeredTime,
		Owner:          c.owner,
		ID:             c.taskID,
		Config:         c.config,
		State:          state,
		ServiceAddress: c.serviceAddress,
		Addresses:      c.addresses,
		ExitStatus:     c.exitStatus,
		Misc:           c.metadata,
		IsReady:        c.readinessMessageSent,
		AgentUserGroup: c.agentUserGroup,
	}
}
