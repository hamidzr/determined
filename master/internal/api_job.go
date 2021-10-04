package internal

import (
	"context"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/determined-ai/determined/master/internal/resourcemanagers"
	"github.com/determined-ai/determined/master/internal/sproto"
	"github.com/determined-ai/determined/proto/pkg/apiv1"
	"github.com/determined-ai/determined/proto/pkg/jobv1"
)

var notImplementedError = status.Error(codes.Unimplemented, "API not implemented")

// GetJobs TODO.
func (a *apiServer) GetJobs(
	_ context.Context, req *apiv1.GetJobsRequest,
) (resp *apiv1.GetJobsResponse, err error) {
	// TODO pagination and filtering
	// a.sort(resp.Jobs, req.OrderBy, req.SortBy, apiv1.GetJobsRequest_SORT_BY_QUEUE_POSITION)
	// resp, a.paginate(&resp.Pagination, &resp.Jobs, req.Pagination.Offset, req.Pagination.Limit)

	var jobs []*jobv1.Job
	resp = &apiv1.GetJobsResponse{}

	if req.ResourcePool == "" {
		return nil, status.Error(codes.InvalidArgument, "missing resource_pool parameter")
	}

	switch {
	case sproto.UseAgentRM(a.m.system):
		err = a.actorRequest(
			sproto.AgentRMAddr.Child(req.ResourcePool), resourcemanagers.GetJobOrder{}, &jobs,
		)
	case sproto.UseK8sRM(a.m.system):
		err = a.actorRequest(sproto.K8sRMAddr, resourcemanagers.GetJobOrder{}, &jobs)
	default:
		err = status.Error(codes.NotFound, "cannot find appropriate resource manager")
	}
	if err != nil {
		return nil, err
	}
	resp.Jobs = jobs
	return resp, nil
}

// GetJobQueueStats TODO.
func (a *apiServer) GetJobQueueStats(
	_ context.Context, req *apiv1.GetJobQueueStatsRequest,
) (resp *apiv1.GetJobQueueStatsResponse, err error) {
	return nil, notImplementedError
}

// UpdateJobQueue TODO.
func (a *apiServer) UpdateJobQueue(
	_ context.Context, req *apiv1.UpdateJobQueueRequest,
) (resp *apiv1.UpdateJobQueueResponse, err error) {
	return nil, notImplementedError
}
