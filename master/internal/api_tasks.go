package internal

import (
	"context"
	"fmt"

	"github.com/determined-ai/determined/proto/pkg/apiv1"
)

func (a *apiServer) GetTasks(
	_ context.Context, req *apiv1.GetTasksRequest) (resp *apiv1.GetTasksResponse, err error) {
	err = a.actorRequest("/tasks", req, &resp)
	return resp, err
}

func (a *apiServer) GetTask(
	_ context.Context, req *apiv1.GetTaskRequest) (resp *apiv1.GetTaskResponse, err error) {
	err = a.actorRequest(fmt.Sprintf("/tasks/%s", req.TaskId), req, &resp)
	return resp, err
}
