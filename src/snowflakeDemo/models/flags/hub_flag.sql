{{config(enabled=false,
pre_hook= 'CREATE VIEW V_COUNT AS SELECT COUNT(CUSTOMER_NAME) FROM DV_PROTOTYPE_DB.SRC.V_HISTORY')}}