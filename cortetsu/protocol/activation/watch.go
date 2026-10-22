package activation

import (
	"bytes"
	"context"
	"encoding/binary"
	"golang.org/x/sys/unix"
	"os"
	"time"
)

// Watch uses inotify after the first opt-in creates the private configuration
// directory. Merely observing never creates an XDG state/config file.
func (s Store) Watch(ctx context.Context, out chan<- struct{}) error {
	notify := func() {
		select {
		case out <- struct{}{}:
		default:
		}
	}
	for ctx.Err() == nil {
		if err := privateDir(s.Root); err != nil {
			timer := time.NewTimer(time.Second)
			select {
			case <-ctx.Done():
				timer.Stop()
				return nil
			case <-timer.C:
			}
			continue
		}
		fd, err := unix.InotifyInit1(unix.IN_CLOEXEC | unix.IN_NONBLOCK)
		if err != nil {
			return err
		}
		file := os.NewFile(uintptr(fd), "activation-inotify")
		_, err = unix.InotifyAddWatch(fd, s.Root, unix.IN_MOVED_TO|unix.IN_MOVED_FROM|unix.IN_CLOSE_WRITE|unix.IN_DELETE|unix.IN_DELETE_SELF|unix.IN_MOVE_SELF)
		if err != nil {
			file.Close()
			continue
		}
		stop := context.AfterFunc(ctx, func() { _ = file.Close() })
		notify() // Re-read once after arming to close the creation/watch race.
		buffer := make([]byte, 8192)
		for ctx.Err() == nil {
			n, err := file.Read(buffer)
			if err != nil {
				break
			}
			lost := false
			for offset := 0; offset+unix.SizeofInotifyEvent <= n; {
				mask := binary.NativeEndian.Uint32(buffer[offset+4 : offset+8])
				length := int(binary.NativeEndian.Uint32(buffer[offset+12 : offset+16]))
				end := offset + unix.SizeofInotifyEvent + length
				if end > n {
					break
				}
				name := string(bytes.TrimRight(buffer[offset+unix.SizeofInotifyEvent:end], "\x00"))
				if name == "activation.json" || mask&unix.IN_Q_OVERFLOW != 0 {
					notify()
				}
				if mask&(unix.IN_IGNORED|unix.IN_DELETE_SELF|unix.IN_MOVE_SELF) != 0 {
					notify()
					lost = true
				}
				offset = end
			}
			if lost {
				break
			}
		}
		stop()
		file.Close()
	}
	return nil
}
