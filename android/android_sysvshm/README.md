# android_sysvshm

SysV shared memory (`shmget`/`shmat`/`shmdt`/`shmctl`) for Android Bionic,
which lacks native SysV IPC. Implements the standard API by talking to a
server process over a Unix domain socket.

Based on https://github.com/pelya/android-shmem (originally for Winlator).

## Build

```bash
./build-x86_64.sh    # x86_64
./build-aarch64.sh   # aarch64
# or
make
```

The main Wine build scripts (`build-scripts/build-step-{x86_64,arm64ec}.sh
--build-sysvshm`) build this automatically and copy the result to
`$deps/lib/libandroid-sysvshm.so`.

## Runtime

Requires `ANDROID_SYSVSHM_SERVER` set to the path of the SysV SHM server
socket.

## API

- `int shmget(key_t key, size_t size, int flags)`
- `void *shmat(int shmid, const void *shmaddr, int shmflg)`
- `int shmdt(const void *shmaddr)`
- `int shmctl(int shmid, int cmd, struct shmid_ds *buf)`
