#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <pthread.h>
#include <unistd.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <sys/stat.h>

#define WORKING 1
#define ON_BREAK 0
#define STOPPED -1

typedef struct {
    int worker_status;
    int working_hours;
    float salary;
    int category_bonus;
} WorkerData;

pthread_mutex_t lock1;
pthread_t bonus_thread;
int running = 1;
WorkerData* shared_data;
int worker_id;
int shmid;

void handle_signal(int sig) {
    pthread_mutex_lock(&lock1);
    if (sig == SIGUSR1) {
        shared_data->worker_status = ON_BREAK;
    }
    else if (sig == SIGUSR2) {
        shared_data->worker_status = WORKING;
    }
    else if (sig == SIGTERM) {
        shared_data->worker_status = STOPPED;
        running = 0;
    }
    pthread_mutex_unlock(&lock1);
}

void* bonus_calculator(void* arg) {
    WorkerData* data = (WorkerData*)arg;
    while (running) {
        pthread_mutex_lock(&lock1);
        if (data->worker_status == WORKING && data->working_hours > 8) {
            data->salary += 5 * data->category_bonus;
        }
        pthread_mutex_unlock(&lock1);
        sleep(1);
    }
    return NULL;
}

void log_worker_status() {
    FILE* log_file;
    char log_filename[50];
    sprintf(log_filename, "worker_%d.log", worker_id);
    log_file = fopen(log_filename, "a");
    if (log_file != NULL) {
        fprintf(log_file, "[Worker %d] Hours Worked: %d, Current Salary: %.2f\n",
            worker_id, shared_data->working_hours, shared_data->salary);
        fclose(log_file);
    }
    else {
        fprintf(stderr, "Error: Unable to open log file for worker %d\n", worker_id);
    }
}

void start_worker(int worker_id) {
    pid_t pid = fork();
    if (pid < 0) {
        perror("Fork failed");
        exit(1);
    }
    if (pid > 0) {
        exit(0);
    }
    if (setsid() < 0) {
        exit(EXIT_FAILURE);
    }
    //chdir("/");
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
    key_t key;
    char key_file[50];
    snprintf(key_file, sizeof(key_file), "worker_%d.key", worker_id);
    FILE* f = fopen(key_file, "w");
    if (f == NULL) {
        perror("fopen");
        exit(EXIT_FAILURE);
    }

    key = ftok(key_file, 65);
    if (key == -1) {
        perror("ftok");
        exit(EXIT_FAILURE);
    }
    fprintf(f, "%d", key);
    fclose(f);

    shmid = shmget(key, sizeof(WorkerData), 0666 | IPC_CREAT);
    if (shmid == -1) {
        perror("shmget");
        exit(EXIT_FAILURE);
    }
    shared_data = (WorkerData*)shmat(shmid, (void*)0, 0);
    if (shared_data == (void*)-1) {
        perror("shmat");
        exit(EXIT_FAILURE);
    }

    shared_data->worker_status = WORKING;
    shared_data->working_hours = 0;
    shared_data->salary = 0.0;
    shared_data->category_bonus = 1;

    if (pthread_mutex_init(&lock1, NULL) != 0) {
        fprintf(stderr, "Mutex init failed\n");
        exit(EXIT_FAILURE);
    }
    if (pthread_create(&bonus_thread, NULL, bonus_calculator, (void*)shared_data) != 0) {
        fprintf(stderr, "Error creating bonus calculation thread\n");
        exit(EXIT_FAILURE);
    }

    while (running) {
        pthread_mutex_lock(&lock1);
        if (shared_data->worker_status == WORKING) {
            shared_data->working_hours++;
            shared_data->salary += 10;
            log_worker_status();
        }
        pthread_mutex_unlock(&lock1);
        sleep(1);

        if (shared_data->salary >= 1000) {
            pthread_mutex_lock(&lock1);
            shared_data->worker_status = STOPPED;
            running = 0;
            pthread_mutex_unlock(&lock1);
        }
    }

    pthread_join(bonus_thread, NULL);
    pthread_mutex_destroy(&lock1);
    shmdt(shared_data);
    shmctl(shmid, IPC_RMID, NULL);
}

int main(int argc, char* argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <worker_id>\n", argv[0]);
        return 1;
    }

    worker_id = atoi(argv[1]);

    signal(SIGUSR1, handle_signal);
    signal(SIGUSR2, handle_signal);
    signal(SIGTERM, handle_signal);
    start_worker(worker_id);

    return 0;
}