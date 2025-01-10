#!/bin/bash
# Worker Management CLI Interface
echo "Welcome to the Worker Management System"
echo "---------------------------------------"

# Function to display menu
show_menu() {
    echo -e "\nOptions:"
    echo "1. Create a Worker Process (Daemon)"
    echo "2. Create Multiple Worker Processes (Daemons)"
    echo "3. View Worker Status"
    echo "4. Send Break Signal (SIGUSR1)"
    echo "5. Resume Work (SIGUSR2)"
    echo "6. Stop Worker Process (SIGTERM)"
    echo "7. List Active Workers and Salaries"
    echo "8. View Working Hours and Bonuses"
    echo "9. Exit"
    echo -n "Enter your choice: "
}

# Function to create a worker process (daemon)
create_worker_process() {
    read -p "Enter Worker ID: " worker_id
    
   nohup ./worker_management_daemon "$worker_id" > "worker_${worker_id}.log" 2>&1 &  
    echo $! > "worker_${worker_id}.pid"
    echo "Worker process created with Worker ID: $worker_id and PID: $!"
    echo "Logs are saved in worker_${worker_id}.log"
}

# Function to create multiple worker processes
create_multiple_workers() {
    read -p "Enter the number of workers to create: " num_workers
    for ((i = 1; i <= num_workers; i++)); do
        read -p "Enter Worker ID for Worker $i: " worker_id
        nohup ./worker_management_daemon "$worker_id" > "worker_${worker_id}.log" 2>&1 &
        echo $! > "worker_${worker_id}.pid"
        echo "Worker process created with Worker ID: $worker_id and PID: $!"
        echo "Logs are saved in worker_${worker_id}.log"
    done
}

# Function to view worker status
view_status() {
    read -p "Enter Worker ID: " worker_id

    # Read the key from the key file
    key_file="worker_${worker_id}.key"
    if [[ ! -f $key_file ]]; then
        echo "Error: Key file for Worker ID $worker_id not found."
        return
    fi

    key=$(cat "$key_file")
    hex_key=$(printf "0x%x" "$key")
    shared_mem=$(ipcs -m | grep "$hex_key" | awk '{print $2}')

    if [[ -z "$shared_mem" ]]; then
        echo "Error: Shared memory for Worker ID $worker_id not found."
        return
    fi

    echo "Fetching status for Worker ID: $worker_id..."
    ipcs -m -i "$shared_mem" | tail -n +6
    echo "---------------------------------------"
    tail "worker_${worker_id}.log" -n 1
}

# Function to send signal to a worker process
send_signal() {
    signal=$1
    read -p "Enter Worker ID: " worker_id
    if [[ -f "worker_${worker_id}.pid" ]]; then
        pid=$(cat "worker_${worker_id}.pid")
        kill -$signal $pid
        echo "Signal $signal sent to worker process (Worker ID: $worker_id, PID: $pid)."
    else
        echo "Error: No PID file found for Worker ID: $worker_id. Worker may not be running."
    fi
}

# Function to stop a worker process
stop_worker_process() {
    read -p "Enter Worker ID to stop: " worker_id
    send_signal SIGTERM
    if [[ -f "worker_${worker_id}.pid" ]]; then
        rm "worker_${worker_id}.pid"
    fi
    if [[ -f "worker_${worker_id}.key" ]]; then
        rm "worker_${worker_id}.key"
    fi
    echo "Worker process for Worker ID: $worker_id has been stopped and its files were removed."
}

# Function to list all active workers and their salaries
list_active_workers() {
    echo "Active Workers and Their Salaries:"
    echo "--------------------------------"
    
    for pid_file in worker_*.pid; do
        if [[ -f $pid_file ]]; then
            worker_id=$(echo $pid_file | sed 's/worker_\(.*\)\.pid/\1/')
            pid=$(cat "$pid_file")
            
            if [[ -f "worker_${worker_id}.log" ]]; then
                last_log=$(tail -n 1 "worker_${worker_id}.log")
                if [[ $last_log =~ \[Worker\ [0-9]+\]\ Hours\ Worked:\ ([0-9]+),\ Current\ Salary:\ ([0-9.]+) ]]; then
                    hours="${BASH_REMATCH[1]}"
                    salary="${BASH_REMATCH[2]}"
                    
                    # Check if process is still running
                    if kill -0 "$pid" 2>/dev/null; then
                        echo "Worker $worker_id:"
                        echo "  - Status: ACTIVE"
                        echo "  - Hours Worked: $hours"
                        echo "  - Current Salary: \$$salary"
                        echo "--------------------------------"
                    else 
                        echo "The process isn't running"      
                    fi
                else 
                    echo "There's a problem with reading the log file"  
                fi
            else 
                echo "There's a problem with the log file"    
            fi
        else 
            echo "There's a problem with the PID file"
        fi
    done
}

# Function to view working hours and bonuses
view_hours_and_bonuses() {
    echo "Working Hours and Bonuses Summary:"
    echo "--------------------------------"
    
    # Loop through all .pid files to find workers
    for pid_file in worker_*.pid; do
        if [[ -f $pid_file ]]; then
            worker_id=$(echo $pid_file | sed 's/worker_\(.*\)\.pid/\1/')
            pid=$(cat "$pid_file")
            
            echo "Worker ID: $worker_id"
            if [[ -f "worker_${worker_id}.log" ]]; then
                # Extract the last line containing hours worked
                last_log=$(tail -n 1 "worker_${worker_id}.log")
                if [[ $last_log =~ Hours\ Worked:\ ([0-9]+) ]]; then
                    hours="${BASH_REMATCH[1]}"
                    echo "  - Hours Worked: $hours"
                fi
                
                # Calculate bonus (assuming it's in the log)
                if [[ $last_log =~ Current\ Salary:\ ([0-9.]+) ]]; then
                    salary="${BASH_REMATCH[1]}"
                    # Base salary is 10 per hour, so bonus is the difference
                    base_salary=$(( hours * 10 ))
                    bonus=$(echo "$salary - $base_salary" | bc)
                    echo "  - Base Salary: $base_salary"
                    echo "  - Total Bonus: $bonus"
                fi
                echo "--------------------------------"
            else
                echo "  - No log file found"
                echo "--------------------------------"
            fi
        fi
    done
}

# Main script loop
while true; do
    show_menu
    read choice
    case $choice in
        1)
            create_worker_process
            ;;
        2)
            create_multiple_workers
            ;;
        3)
            view_status
            ;;
        4)
            send_signal SIGUSR1
            ;;
        5)
            send_signal SIGUSR2
            ;;
        6)
            stop_worker_process
            ;;
        7)
            list_active_workers
            ;;
        8)
            view_hours_and_bonuses
            ;;
        9)
            echo "Exiting Worker Management System."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please try again."
            ;;
    esac
done
