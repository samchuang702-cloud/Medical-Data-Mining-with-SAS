/*==========================================================================
  Medical Data Mining Final Project
  Pneumonia mortality risk prediction — SAS EG preprocessing workflow

  Privacy note:
  This repository does not include any patient-level or restricted data.
  Update PROJECT_PATH before running with legally authorized datasets.
==========================================================================*/

%let project_path = C:\path\to\authorized\project_data;
libname PROJECT "&project_path.";

/*--------------------------------------------------------------------------
  1. Select pneumonia inpatient records (ICD-9-CM primary diagnosis 486)
--------------------------------------------------------------------------*/
proc sql;
    create table work.pneumonia_ipd as
    select
        ID,
        HOSP_ID,
        FEE_YM,
        IN_DATE as INDEX_DATE label='Index date',
        IN_AGE as AGE label='Age',
        ICD9CM_1,
        ID_S,
        CITY,
        'IPD' as SOURCE length=3
    from PROJECT.IPD
    where ICD9CM_1 = '486'
      and ID_S ne '9';
quit;

/*--------------------------------------------------------------------------
  2. Combine outpatient files and select pneumonia visits
--------------------------------------------------------------------------*/
proc sql;
    create table work.opd_all as
    select * from PROJECT.OPD_1
    outer union corr
    select * from PROJECT.OPD_2
    outer union corr
    select * from PROJECT.OPD_3
    outer union corr
    select * from PROJECT.OPD_4;

    create table work.pneumonia_opd as
    select
        ID,
        HOSP_ID,
        FEE_YM,
        FUNC_DATE,
        AGE,
        ICD9CM_1,
        ICD9CM_2,
        ICD9CM_3,
        ID_S,
        CITY,
        'OPD' as SOURCE length=3
    from work.opd_all
    where ICD9CM_1 = '486';
quit;

/*--------------------------------------------------------------------------
  3. Combine outpatient and inpatient pneumonia records
--------------------------------------------------------------------------*/
proc sql;
    create table work.pneumonia_claims as
    select * from work.pneumonia_opd
    outer union corr
    select * from work.pneumonia_ipd;
quit;

/*--------------------------------------------------------------------------
  4. Create utilization and comorbidity features
--------------------------------------------------------------------------*/
proc sql;
    create table work.claim_features as
    select
        *,
        case when SOURCE = 'IPD' then 1 else 0 end as IS_IPD,
        case
            when (ICD9CM_1 between '490' and '496')
              or (ICD9CM_2 between '490' and '496')
              or (ICD9CM_3 between '490' and '496')
            then 1 else 0
        end as COPD,
        case
            when ICD9CM_1 = '250' or ICD9CM_2 = '250' or ICD9CM_3 = '250'
            then 1 else 0
        end as DM,
        case
            when ICD9CM_1 = '428' or ICD9CM_2 = '428' or ICD9CM_3 = '428'
            then 1 else 0
        end as CHF,
        case
            when ICD9CM_1 = '585' or ICD9CM_2 = '585' or ICD9CM_3 = '585'
            then 1 else 0
        end as CKD
    from work.pneumonia_claims;
quit;

/*--------------------------------------------------------------------------
  5. Create demographic and target features from the authorized cohort table

  Expected columns in PROJECT.OPDIPD_6_20191203:
  ID, AGE, ID_S, COUNTY, AGE_GROUP, DEATH, INDEX_DATE
--------------------------------------------------------------------------*/
proc sql;
    create table work.patient_features as
    select
        ID,
        ID_S,
        DEATH,
        INDEX_DATE,
        case
            when index(AGE, '天') > 0 then 0
            else input(compress(AGE, '歲以上'), 8.)
        end as AGE_NUM,
        case when input(compress(AGE, '歲'), 8.) >= 65 then 1 else 0 end as ELDERLY,
        case when input(compress(AGE, '歲'), 8.) >= 80 then 1 else 0 end as AGE80,
        case
            when COUNTY in ('台北市','新北市','桃園縣','基隆市','新竹市','新竹縣') then '北部'
            when COUNTY in ('台中市','彰化縣','南投縣','苗栗縣') then '中部'
            when COUNTY in ('高雄市','台南市','嘉義市','嘉義縣','屏東縣','雲林縣') then '南部'
            else '東部'
        end as REGION length=6,
        case
            when input(compress(AGE, '歲'), 8.) < 10 then 1
            when input(compress(AGE, '歲'), 8.) < 20 then 2
            when input(compress(AGE, '歲'), 8.) < 30 then 3
            when input(compress(AGE, '歲'), 8.) < 40 then 4
            when input(compress(AGE, '歲'), 8.) < 50 then 5
            when input(compress(AGE, '歲'), 8.) < 60 then 6
            when input(compress(AGE, '歲'), 8.) < 70 then 7
            when input(compress(AGE, '歲'), 8.) < 80 then 8
            else 9
        end as AGE_GROUP
    from PROJECT.OPDIPD_6_20191203;
quit;

/*--------------------------------------------------------------------------
  6. Join features and keep one record per patient
--------------------------------------------------------------------------*/
proc sql;
    create table work.model_features_raw as
    select
        c.SOURCE,
        c.IS_IPD,
        c.COPD,
        c.DM,
        c.CHF,
        c.CKD,
        p.ID_S,
        p.DEATH,
        p.AGE_NUM,
        p.ELDERLY,
        p.AGE80,
        p.REGION,
        p.AGE_GROUP,
        p.INDEX_DATE,
        p.ID
    from work.claim_features c
    left join work.patient_features p
      on c.ID = p.ID;
quit;

proc sort data=work.model_features_raw
          out=PROJECT.MODEL_READY
          nodupkey;
    by ID;
run;

/* MODEL_READY can now be registered as a SAS Enterprise Miner data source.
   Recommended roles:
     Target: DEATH
     Inputs: SOURCE, IS_IPD, COPD, DM, CHF, CKD, ID_S, AGE_NUM,
             ELDERLY, AGE80, REGION, AGE_GROUP
     Rejected/ID: ID, INDEX_DATE
*/

