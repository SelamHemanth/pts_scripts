#!/bin/bash

set -x

# Print the current working directory and list files
echo "Current directory: $(pwd)"
echo "Listing files:"
ls -l

transform_result_name() {
    local result_name="$1"
    echo "${result_name//\//}"
}

run_phoronix_test() {
    local test_name="$1"
    local kernel_version
    kernel_version=$(uname -r)
    local result_name="$test_name"
    local transformed_result_name
    transformed_result_name=$(transform_result_name "$result_name")-$(date +%Y%m%d-%H%M%S)
    local unique_name="Test run for $test_name on kernel $kernel_version at $(date +%Y%m%d%H%M%S)"

    echo "transformed_result_name: $transformed_result_name"

    local start_time
    start_time=$(date +%s)
    echo "Test started at: $(date -d @$start_time)"

    # Create the directory if it doesn't exist
    mkdir -p $HOME/.phoronix-test-suite/test-results/$transformed_result_name

    # Read NGINX_OPTIONS from .config.options
    if [ -f .config.options ]; then
        pgbench_option1=$(grep "PGBENCH_OPTIONS1=" .config.options | cut -d'=' -f2)
        pgbench_option2=$(grep "PGBENCH_OPTIONS2=" .config.options | cut -d'=' -f2)
        pgbench_option3=$(grep "PGBENCH_OPTIONS3=" .config.options | cut -d'=' -f2)
        echo "pgbench_option1: $pgbench_option1"
        echo "pgbench_option2: $pgbench_option2"
        echo "pgbench_option3: $pgbench_option3"
    else
        echo ".config.options file not found!"
        exit 1
    fi

    expect << EOF | tee $HOME/.phoronix-test-suite/test-results/$transformed_result_name/expect.log
        set timeout -1
        spawn phoronix-test-suite benchmark $test_name
        expect "Scaling Factor:" { send "$pgbench_option1\r" }
        expect "Clients:" { send "$pgbench_option2\r" }
        expect "Mode:" { send "$pgbench_option3\r" }
        expect "Would you like to save these test results (Y/n):" { send "Y\r" }
        expect "Enter a name for the result file:" { send "$transformed_result_name\r" }
        expect "Enter a unique name to describe this test run / configuration:" { send "$unique_name\r" }
        expect "New Description:" { send "Automated test run for pts/nginx on this system.\r" }
        expect {
            "Do you want to view the results in your web browser (Y/n):" { send "n\r"; exp_continue }
            "Would you like to upload the results to OpenBenchmarking.org (y/n):" { send "n\r"; exp_continue }
            "Do you want to view the text-based test results? (Y/n):" { send "n\r" }
        }
        expect eof
EOF

    local end_time
    end_time=$(date +%s)
    echo "Test completed at: $(date -d @$end_time)"
    echo "Duration: $((end_time - start_time)) seconds"

    # Extract data after the test completes
    echo "Extracting data"
    # Path to the XML file
    XML_FILE="/home/amd/.phoronix-test-suite/test-results/${transformed_result_name}/composite.xml"
    OPT_FILE="/home/amd/.phoronix-test-suite/test-results/${transformed_result_name}/${transformed_result_name}_result.txt"
    # Extract and print all test results
    extract_results
    echo "Data extraction completed"
}

# Function to extract and print test results
extract_results() {
    local result_count=$(xmllint --xpath "count(/PhoronixTestSuite/Result)" $XML_FILE)
    local title=${transformed_result_name}
    echo "==============================" >> $OPT_FILE
    echo "Title: $title" >> $OPT_FILE
    echo "==============================" >> $OPT_FILE
    echo "                              " >> $OPT_FILE
    for ((i=1; i<=result_count; i++)); do
        local description=$(xmllint --xpath "string(/PhoronixTestSuite/Result[$i]/Description)" $XML_FILE)
        local scale=$(xmllint --xpath "string(/PhoronixTestSuite/Result[$i]/Scale)" $XML_FILE)
        local value=$(xmllint --xpath "string(/PhoronixTestSuite/Result[$i]/Data/Entry/Value)" $XML_FILE)
        echo "$description" >> $OPT_FILE
        echo "$value	$scale" >> $OPT_FILE
	echo "" >> $OPT_FILE
    done
    echo "==============================" >> $OPT_FILE
}

# Run the Phoronix test
test_name="pts/pgbench"
run_phoronix_test "$test_name"

