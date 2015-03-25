package amazon

import (
	"errors"
	"koding/kites/kloud/eventer"
	"koding/kites/kloud/machinestate"
	"koding/kites/kloud/waitstate"
	"strings"

	"github.com/mitchellh/goamz/ec2"
	"golang.org/x/net/context"
)

func (a *Amazon) Start(ctx context.Context) (ec2.Instance, error) {
	ev, withPush := eventer.FromContext(ctx)
	if !withPush {
		return ec2.Instance{}, errors.New("eventer context is not available")
	}

	if withPush {
		ev.Push(&eventer.Event{
			Message:    "Starting machine",
			Status:     machinestate.Starting,
			Percentage: 10,
		})
	}

	_, err := a.Client.StartInstances(a.Id())
	if err != nil {
		return ec2.Instance{}, err
	}

	var instance ec2.Instance
	stateFunc := func(currentPercentage int) (machinestate.State, error) {
		instance, err = a.Instance()
		if err != nil {
			return 0, err
		}

		return StatusToState(instance.State.Name), nil
	}

	ws := waitstate.WaitState{
		StateFunc: stateFunc,
		Eventer:   ev,
		Action:    "start",
		Start:     25,
		Finish:    60,
	}

	if err := ws.Wait(); err != nil {
		return ec2.Instance{}, err
	}

	return instance, nil
}

func (a *Amazon) Stop(ctx context.Context) error {
	ev, withPush := eventer.FromContext(ctx)
	if !withPush {
		return errors.New("eventer context is not available")
	}

	if withPush {
		ev.Push(&eventer.Event{
			Message:    "Stopping machine",
			Status:     machinestate.Stopping,
			Percentage: 10,
		})
	}

	_, err := a.Client.StopInstances(a.Id())
	if err != nil {
		return err
	}

	stateFunc := func(currentPercentage int) (machinestate.State, error) {
		instance, err := a.Instance()
		if err != nil {
			return 0, err
		}

		return StatusToState(instance.State.Name), nil
	}

	ws := waitstate.WaitState{
		StateFunc: stateFunc,
		Eventer:   ev,
		Action:    "stop",
		Start:     25,
		Finish:    60,
	}

	return ws.Wait()
}

func (a *Amazon) Restart(ctx context.Context) error {
	ev, withPush := eventer.FromContext(ctx)
	if !withPush {
		return errors.New("eventer context is not available")
	}

	if withPush {
		ev.Push(&eventer.Event{
			Message:    "Restarting machine",
			Status:     machinestate.Rebooting,
			Percentage: 10,
		})
	}

	_, err := a.Client.RebootInstances(a.Id())
	if err != nil {
		return err
	}

	stateFunc := func(currentPercentage int) (machinestate.State, error) {
		instance, err := a.Instance()
		if err != nil {
			return 0, err
		}

		return StatusToState(instance.State.Name), nil
	}

	ws := waitstate.WaitState{
		StateFunc: stateFunc,
		Eventer:   ev,
		Action:    "restart",
		Start:     25,
		Finish:    60,
	}

	return ws.Wait()
}

func (a *Amazon) Destroy(ctx context.Context, start, finish int) error {
	ev, withPush := eventer.FromContext(ctx)
	if !withPush {
		return errors.New("eventer context is not available")
	}

	if a.Id() == "" {
		return errors.New("instance id is empty")
	}

	if withPush {
		ev.Push(&eventer.Event{
			Message:    "Terminating machine",
			Status:     machinestate.Terminating,
			Percentage: start,
		})
	}

	_, err := a.Client.TerminateInstances([]string{a.Id()})
	if err != nil {
		return err
	}

	stateFunc := func(currentPercentage int) (machinestate.State, error) {
		instance, err := a.Instance()
		if err != nil {
			return 0, err
		}

		return StatusToState(instance.State.Name), nil
	}

	ws := waitstate.WaitState{
		StateFunc: stateFunc,
		Eventer:   ev,
		Action:    "destroy",
		Start:     start,
		Finish:    finish,
	}

	return ws.Wait()
}

// StatusToState converts a amazon status to a sensible machinestate.State
// format
func StatusToState(status string) machinestate.State {
	status = strings.ToLower(status)

	// Valid values: pending | running | shutting-down | terminated | stopping | stopped

	switch status {
	case "pending":
		return machinestate.Starting
	case "running":
		return machinestate.Running
	case "stopped":
		return machinestate.Stopped
	case "stopping":
		return machinestate.Stopping
	case "shutting-down":
		return machinestate.Terminating
	case "terminated":
		return machinestate.Terminated
	default:
		return machinestate.Unknown
	}
}
