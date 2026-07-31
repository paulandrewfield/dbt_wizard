/**********************************************************************
 *  PROC    : BUILD_STG_TPCH_SUPPLIERS
 *  AUTHOR  : G. WOZNIAK (DBA)
 *  CREATED : 2018-11-11
 *  PURPOSE : STAGE RAW SUPPLIER DATA.
 *  MODIFIED: 2019-05-30 GW - ADDED ROW_COUNT = 1 SO REPORTING CAN
 *                            SUM IT INSTEAD OF LEARNING COUNT(*).
 *                            NOT MY CIRCUS. IT WORKS. MOVING ON.
 *  MODIFIED: 2021-08-02 dpatel - reformatted to house standard while I was
 *            in here for the phone thing. gw's caps hurt to read. also the
 *            phone thing turned out to be a source problem so nothing
 *            changed, only the layout. sorry greg.
 *  PG PORT : Snowflake SQL proc -> PL/pgSQL; source -> public.supplier.
 **********************************************************************/
Create Or Replace Procedure retail_datamart.build_stg_tpch_suppliers()
Language plpgsql
Set search_path = retail_datamart, public
As
$$
Declare
    strTbl   Text := 'stg_tpch_suppliers';
    intRows  Integer;
Begin

    Drop Table If Exists retail_datamart.stg_tpch_suppliers;

    Create Table retail_datamart.stg_tpch_suppliers
    (
        supplier_key        numeric(38,0),
        supplier_name       varchar,
        supplier_address    varchar,
        nation_key          numeric(38,0),
        phone_number        varchar,
        account_balance     numeric(12,2),
        comment             varchar,
        row_count           numeric(38,0)
    );

    Insert Into retail_datamart.stg_tpch_suppliers
    (
        supplier_key, supplier_name, supplier_address, nation_key,
        phone_number, account_balance, comment, row_count
    )
    Select  sup.s_suppkey    supplier_key
    ,       sup.s_name       supplier_name
    ,       sup.s_address    supplier_address
    ,       sup.s_nationkey  nation_key
    ,       sup.s_phone      phone_number
    ,       sup.s_acctbal    account_balance
    ,       sup.s_comment    comment
    ,       1                row_count   -- HARDCODED 1. SEE HEADER. DON'T ASK.
    From    public.supplier  sup
    Where   sup.s_suppkey Is Not Null
    Order By 1;

    Get Diagnostics intRows = Row_Count;

    If intRows = 0 Then
        Raise Warning '% loaded zero rows', strTbl;
    End If;

    Raise Notice 'stg_tpch_suppliers built';

End;
$$;
