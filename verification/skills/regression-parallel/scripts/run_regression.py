#!/usr/bin/env python3
# Calling convention:
# ./run_regression.py -t doc/msic_a0_verification_plan.ods -r run_regr
import sys, os, math, argparse, re, subprocess
# NOTE: you need to install the pandas-ods-reader package.
# command: pip install pandas-ods-reader
from pandas_ods_reader import read_ods
import pandas

from pathlib import Path

import datetime as dt

test_dict = dict()
list_of_tests = ["spi_page_write_test", "spi_host_test1", "spi_read_status_registers_test", "clock_ctrl_test1"]
# Regex pattern to match test name and status
test_status_pattern = r'^([a-z_][a-z0-9_]*)\s+(PASS|FAIL)$'

base_path = os.path.join(os.getcwd(), '../../firmware/msic_tests')

# copmile_testcase Python method.
# This method requires:
#  1. a testcase name to set the Makefile TESTNAME argument from the command line
#  2. a path to the testcase as an input argument.
# From there, the method will spawn a subprocess to compile the testcase by executing "make clean all" in the supplied
# testcase directory.
# After the testcase has been compiled, we need to verify that the compilation process completed successfully.
# we will do that by checking the numerical result of the compile command.
# Eventually we will also need to check for the existence of the verilog arm.bin file.
def compile_testcase(testname, project_path):
    print("Compiling testcase")
    try:
        # Ensure the path exists
        if not Path(project_path).is_dir():
            print(f"Skipping: {project_path} (not a directory)")
            return False

        # Run 'make' or gcc command in that directory
        result = subprocess.run(
            ["make", "clean", "all", f"TESTNAME={testname}"],  # Change to ["gcc", "main.c", "-o", "main"] if no Makefile
            cwd=project_path,
            universal_newlines=True, # returns strings instead of bytes
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True
        )
        print(result.stdout)

        print(f"Compiled successfully: {project_path}")
        return True
    # Check compilation results
    except subprocess.CalledProcessError as e:
        print(f"Compilation failed: {project_path}")
        print(f"Return code: {e.returncode}")
        print(f"stdout: {e.stdout}")
        print(f"stderr: {e.stderr}")
        return False
    except Exception as e:
        print(f"Error compiling {project_path}: {e}")
        return False

# Brief: this will actually call the bash regression script in a subprocess call. 
# 
# arguments: regr_script
# return values:
#     return: an integer value from the run_regr bash script.
#             0 = success
#             >=1 (or any nonzero return value) = fail
#                                                 Github actions will consume this value and report a pass/fail based
#                                                 on it
def run_regression(regr_script):
    print("Running regression")
    result = subprocess.run(
            [f"./{regr_script}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=120,
            check=True
    )
    print(result.stdout)
    return result

# this will call compile_testcase for each test listed in the testplae for each test listed in the testplann
# this will then call run_regression
# arguments:
#     testplan_path: a string that representsthe testplan name and location in the git repository
# return value:
#     result: should be an object of both stdout and stderr from run_regr bash script invocation
def read_testplan(testplan_path):
    print("Reading testplan ODS file")
    if not os.path.isfile(testplan_path):
        raise FileNotFoundError(f"ERROR: regression file not found")
        sys.exit(1)
    
    # Read in the 2nd sheet in the testplan.
    testplan = read_ods(testplan_path, 2)
    print("Opened testplan")

    for index, row in testplan.iterrows():
        print("{} Testname: {}, Status: {}".format(row["Priority"], row["Testname"], row["Status"]))
        testpath = os.path.join(base_path, row["Testname"])
        # could also iterate over each subdirectory using the iterdir() method in the Paths module.
        if os.path.isdir(testpath):
            print(testpath)
            compile_testcase(row["Testname"], testpath)
        else:
            print("Testcase not found")
    # Commenting this out. run_regression should be its own function called in main()
    #result = run_regression()
    #return result


# arguments: 
#     testplan: pandas dataframe from the testplan fods file
#     matches: list of tuples from read_regression_logfile()
def update_testplan(testplan, matches):
    print("Updating testplan")
    if not os.path.isfile(testplan):
        raise FileNotFoundError(f"ERROR: regression file not found")
        sys.exit(1)
    
    # Read in the 2nd sheet in the testplan.
    testplan = read_ods(testplan, 2)
    print("Opened testplan")
    match_index = 0
    for index, row in testplan.iterrows():
        print("{} Testname: {}, Status: {}".format(row["Priority"], row["Testname"], row["Status"]))

    for match in matches:
        testname, status = match[0], match[1]
        print(f"Updating test status for {testname}")

        # Boolean filtering to get matching rows
        mask = testplan["Testname"] == testname

        if mask.any():
            # Get the index (could be multiple matches)
            testplan.loc[mask, "Status"] = status
            print(f"Updated {mask.sum()} row(s) for {testname} to {status}")
        else:
            print(f"WARNING: No test named {testname} in MSIC A0 testplan.")

    # show updated testplan
    for index, row in testplan.iterrows():
        print("{} Testname: {}, Status: {}".format(row["Priority"], row["Testname"], row["Status"]))

    # TODO: decide if we want to update Version and Doc Info every time Github Actions runs
    sheet_1 = read_ods(testplan, 1)
    with pandas.ExcelWriter(testplan, engine="odf") as writer:
        sheet_1.to_excel(writer, sheet_name="Version and Doc Info", index=False)
        testplan.to_excel(writer, sheet_name="Testcases", index=False)

    return testplan

def read_regression_logfile(logfile):
    print("Reading regression logfile")
    try:
        with open(logfile, "r") as run_regr_results:
            print("Opened files")
            contents = run_regr_results.read()
            matches = re.findall(test_status_pattern, contents, re.MULTILINE | re.IGNORECASE)
    except FileNotFoundError:
        print(f"ERROR: regression file not found")
        sys.exit(1)
    except Exception as e:
        print(f"Error reading file: {e}")
        sys.exit(1)
    
    print(matches)
    run_regr_results.close() 
    return matches

def main():
    # 3 local variables:
    # 1. result = result of the regression script --> 0 for pass, 1 for fail.
    # 2. matches: list of tuples that we read off of the regression file
    # 3. updated_testplan = a pandas dataframe consisting of the "Testcases" sheet from our testplan.ods file
    parser = argparse.ArgumentParser()
    parser.add_argument("-t", "--testplan", type=str, help="Feed in a testplan for the flow")
    parser.add_argument("-r", "--regrscript", type=str, help="The regression script we need to run")
    args = parser.parse_args()
    read_testplan(args.testplan)
    result = run_regression(args.regrscript)
    logfile = f"{args.regrscript}" + "_" + dt.date.today().strftime("%y-%m-%d") + "_log.txt"
    print(f"Regression logfile: {logfile}")
    logfile_path = os.path.join("run_regr_results", logfile)
    if os.path.exists(logfile_path):
        print("File exists:")
        print(logfile_path)
    else:
        print("Can't find the regression logfile")
        sys.exit(1)
    #matches = read_regression_logfile(args.logfile) # TODO: need to change this from args.logfile to a variable.
    #updated_testplan = update_testplan(matches)
    #TODO: uncomment this after checking with Mark if formatting loss is ok in testplan ODS file

    # Need to return result so Github Actions can capture the output of the regression.
    return result

if __name__ == "__main__":
    main()

