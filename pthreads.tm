# A Posix Threads (pthreads) wrapper
use <pthread.h>

struct Mutex(_mutex:@Memory)
    func new(->Mutex)
        return Mutex(
            C_code : @Memory`
                pthread_mutex_t *mutex = GC_MALLOC(sizeof(pthread_mutex_t));
                pthread_mutex_init(mutex, NULL);
                GC_register_finalizer(mutex, (void*)pthread_mutex_destroy, NULL, NULL, NULL);
                mutex
            `
        )

    func lock(m:Mutex)
        status := C_code:Int32`pthread_mutex_lock(@(m._mutex))`
        fail("Failed to lock Mutex") unless status == 0

    func unlock(m:Mutex)
        status := C_code:Int32`pthread_mutex_unlock(@(m._mutex))`
        fail("Failed to unlock Mutex") unless status == 0

struct Condition(_cond:@Memory)
    func new(->Condition)
        return Condition(
            C_code : @Memory `
                pthread_cond_t *cond = GC_MALLOC(sizeof(pthread_cond_t));
                pthread_cond_init(cond, NULL);
                GC_register_finalizer(cond, (void*)pthread_cond_destroy, NULL, NULL, NULL);
                cond
            `
        )

    func wait(cond:Condition, mutex:Mutex)
        status := C_code:Int32`pthread_cond_wait(@(cond._cond), @(mutex._mutex))`
        fail("Failed to wait on Condition") unless status == 0

    func signal(cond:Condition)
        status := C_code:Int32`pthread_cond_signal(@(cond._cond))`
        fail("Failed to signal Condition") unless status == 0

    func broadcast(cond:Condition)
        status := C_code:Int32`pthread_cond_broadcast(@(cond._cond))`
        fail("Failed to broadcast Condition") unless status == 0

struct RWLock(_rwlock:@Memory)
    func new(->RWLock)
        return RWLock(
            C_code : @Memory `
                pthread_rwlock_t *lock = GC_MALLOC(sizeof(pthread_rwlock_t));
                pthread_rwlock_init(lock, NULL);
                GC_register_finalizer(lock, (void*)pthread_rwlock_destroy, NULL, NULL, NULL);
                lock
            `
        )

    func read_lock(lock:RWLock)
        status := C_code:Int32 `pthread_rwlock_rdlock(@(lock._rwlock))`
        fail("Failed to read-lock RWLock") unless status == 0

    func write_lock(lock:RWLock)
        status := C_code:Int32 `pthread_rwlock_wrlock(@(lock._rwlock))`
        fail("Failed to write-lock RWLock") unless status == 0

    func unlock(lock:RWLock)
        status := C_code:Int32 `pthread_rwlock_unlock(@(lock._rwlock))`
        fail("Failed to unlock RWLock") unless status == 0

struct PThread(_pthread:@Memory)
    func new(fn:func() -> PThread)
        return PThread(
            C_code:@Memory `
                pthread_t *thread = GC_MALLOC(sizeof(pthread_t));
                pthread_create(thread, NULL, @fn.fn, @fn.userdata);
                thread
            `
        )

    func join(p:PThread)
        status := C_code:Int32 `pthread_join(*(pthread_t*)@(p._pthread), NULL)`
        fail("Failed to cancel PThread") if status != 0

    func cancel(p:PThread)
        status := C_code:Int32 `pthread_cancel(*(pthread_t*)@(p._pthread))`
        fail("Failed to cancel PThread") if status != 0

    func detatch(p:PThread)
        status := C_code:Int32 `pthread_detach(*(pthread_t*)@(p._pthread))`
        fail("Failed to detatch PThread") if status != 0

struct IntQueue(_queue:@[Int], _mutex:Mutex, _cond:Condition)
    func new(initial:[Int]=[] -> IntQueue)
        return IntQueue(@initial, Mutex.new(), Condition.new())

    func give(q:IntQueue, n:Int)
        do q._mutex.lock()
            q._queue.insert(n)
            q._mutex.unlock()
        q._cond.signal()

    func take(q:IntQueue -> Int)
        do q._mutex.lock()
            n := q._queue.pop(1)
            while not n
                q._cond.wait(q._mutex)
                n = q._queue.pop(1)
            q._mutex.unlock()
            return n!

func main()
    jobs := IntQueue.new()
    results := IntQueue.new()

    say_mutex := Mutex.new()
    announce := func(speaker:Text, text:Text)
        do say_mutex.lock()
            say("\[2][$speaker]\[] $text")
            say_mutex.unlock()

    worker := PThread.new(func()
        say("I'm in the thread!")
        repeat
            announce("worker", "waiting for job")
            job := jobs.take()
            result := job * 10
            announce("worker", "Jobbing $job into $result")
            results.give(result)
            announce("worker", "Signaled $result")
    )

    for i in 10
        announce("boss", "Pushing job $i")
        jobs.give(i)
        announce("boss", "Gave job $i")

    for i in 10
        announce("boss", "Getting result...")
        result := results.take()
        announce("boss", "Got result $result")

    >> worker.cancel()
