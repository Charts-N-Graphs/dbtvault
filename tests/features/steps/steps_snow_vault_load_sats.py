import os

from behave import *

from definitions import DBT_ROOT

use_step_matcher("parse")


# LOAD STEPS


@step("I load the TEST_SAT_CUSTOMER_DETAILS table")
def step_impl(context):
    os.chdir(DBT_ROOT)
    os.system("dbt run --models +dbtvault.features.load_sats.test_sat_customer_details")


# MAIN STEPS


@step('the TEST_STG_CUSTOMER table has data inserted into it')
def step_impl(context):
    context.testdata.create_schema("DV_PROTOTYPE_DB", "SRC_TEST_STG")
    context.testdata.drop_and_create("DV_PROTOTYPE_DB", "SRC_TEST_STG", "test_stg_customer_details",
                                     ["CUSTOMER_ID VARCHAR(38)", "CUSTOMER_NAME VARCHAR(60)", "CUSTOMER_DOB DATE",
                                      "CUSTOMER_PHONE VARCHAR(15)", "LOADDATE DATE", "SOURCE VARCHAR(4)"],
                                     materialise="table")

    context.testdata.insert_data_from_ct(context.table, "test_stg_customer_details", "SRC_TEST_STG")


@given("I have an empty TEST_SAT_CUSTOMER_DETAILS table")
def step_impl(context):
    context.testdata.drop_and_create("DV_PROTOTYPE_DB", "SRC_TEST_VLT", "test_sat_customer_details",
                                     ["HASHDIFF BINARY(16)", "CUSTOMER_PK BINARY(16)", "NAME VARCHAR(60)",
                                      "PHONE VARCHAR(15)", "DOB DATE", "LOADDATE DATE", "EFFECTIVE_FROM DATE",
                                      "SOURCE VARCHAR(4)"], materialise="table")


@given("there are records in the TEST_SAT_CUSTOMER_DETAILS table")
def step_impl(context):
    context.testdata.create_schema("DV_PROTOTYPE_DB", "SRC_TEST_VLT")
    context.testdata.drop_and_create("DV_PROTOTYPE_DB", "SRC_TEST_VLT", "test_sat_customer_details",
                                     ["HASHDIFF BINARY(16)", "CUSTOMER_PK BINARY(16)", "NAME VARCHAR(60)",
                                      "PHONE VARCHAR(15)", "DOB DATE", "LOADDATE DATE", "EFFECTIVE_FROM DATE",
                                      "SOURCE VARCHAR(4)"],
                                     materialise="table")

    context.testdata.insert_data_from_ct(context.table, "test_sat_customer_details", "SRC_TEST_VLT")


@step("the TEST_SAT_CUSTOMER_DETAILS table should contain")
def step_impl(context):
    table_df = context.testdata.context_table_to_df(context.table, ignore_columns='SOURCE')

    result_df = context.testdata.get_table_data(full_table_name="DV_PROTOTYPE_DB.SRC_TEST_VLT.test_sat_customer_details",
                                                binary_columns=['CUSTOMER_PK', 'HASHDIFF'], ignore_columns='SOURCE',
                                                order_by='NAME')

    assert context.testdata.compare_dataframes(table_df, result_df)


# CYCLE SCENARIO STEPS

@given("I have an empty TEST_SAT_CUST_CUSTOMER table")
def step_impl(context):
    context.testdata.drop_and_create("DV_PROTOTYPE_DB", "SRC_TEST_VLT", "test_sat_cust_customer_details",
                                     ["CUSTOMER_PK BINARY(16)", "HASHDIFF BINARY(16)", "NAME VARCHAR(60)",
                                      "DOB DATE", "EFFECTIVE_FROM DATE", "LOADDATE DATE",
                                      "SOURCE VARCHAR(4)"],
                                     materialise="table")


@step('the TEST_SAT_CUST_CUSTOMER is loaded for day {day_number}')
def step_impl(context, day_number):
    os.chdir(DBT_ROOT)

    os.system("dbt run --models +test_sat_cust_customer_details")
