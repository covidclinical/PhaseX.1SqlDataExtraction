--------------------------------------------------------------------------------
-- Custom cohorts: All other MISC patients (OtherMISCAdm and OtherMISCNotAdm)
-- Database: Microsoft SQL Server
-- Data Model: i2b2
-- Created By: Griffin Weber (weber@hms.harvard.edu)
--
-- This code creates two additional cohorts capturing all patients who are not
-- in any of the cohorts from a given start date (Jan 1, 2017, by default),
-- but are listed in the #fource_misc table.
-- The OtherMISCAdm cohort includes MISC patients who had an inpatient visit,
-- and OtherMISCNotAdm has MISC patients who had no inpatient visit.
--
-- Instructions: Search the 4CE_PhaseX.2_Files_*.sql script for the comment
-- "Add additional custom cohorts here". Right below it insert the contents of
-- this script. To use a different start date, replace "1/1/2017" with the new
-- start date, and replace "1/1/2016" with one year prior to that start date.
-- The script will select all patients who have an encounter on or after the
-- "1/1/2017" date (or whatever you replace it with). It goes back to the
-- "1/1/2016" date to find admissions, ICU encounters, or death dates one year
-- prior to the index date (day 0). If you use a custom database schema, replace
-- "dbo." with the schema name. If you use multiple fact table, adjust the SQL
-- queries as needed.
--------------------------------------------------------------------------------

-- Add admissions for other patients
insert into #fource_admissions
	select *
	from (
		select distinct patient_num, cast(start_date as date) admission_date, isnull(cast(end_date as date),'1/1/2199') discharge_date
		from (
			select patient_num, start_date, end_date
				from dbo.visit_dimension
				where inout_cd in (select local_code from #fource_code_map where code = 'inpatient_inout_cd')
			union all
			select patient_num, start_date, end_date
				from dbo.visit_dimension v
				where location_cd in (select local_code from #fource_code_map where code = 'inpatient_location_cd')
			union all
			select f.patient_num, f.start_date, isnull(f.end_date,v.end_date)
				from dbo.observation_fact f
					inner join dbo.visit_dimension v
						on v.encounter_num=f.encounter_num and v.patient_num=f.patient_num
				where f.concept_cd in (select local_code from #fource_code_map where code = 'inpatient_concept_cd')
		) t
	) t
	where (admission_date >= '1/1/2016') and (discharge_date >= admission_date)
		and patient_num not in (select patient_num from #fource_cohort_patients)
		and patient_num in (select patient_num from #fource_misc)
-- Add ICU dates for other patients
insert into #fource_icu
	select *
	from (
		select distinct patient_num, cast(start_date as date) start_date, isnull(cast(end_date as date),'1/1/2199') end_date
		from (
			select patient_num, start_date, end_date
				from dbo.visit_dimension
				where inout_cd in (select local_code from #fource_code_map where code = 'icu_inout_cd')
			union all
			select patient_num, start_date, end_date
				from dbo.visit_dimension v
				where location_cd in (select local_code from #fource_code_map where code = 'icu_location_cd')
			union all
			select f.patient_num, f.start_date, isnull(f.end_date,v.end_date)
				from dbo.observation_fact f
					inner join dbo.visit_dimension v
						on v.encounter_num=f.encounter_num and v.patient_num=f.patient_num
				where f.concept_cd in (select local_code from #fource_code_map where code = 'icu_concept_cd')
		) t
	) t
	where (start_date >= '1/1/2016') and (end_date >= start_date)
		and patient_num not in (select patient_num from #fource_cohort_patients)
		and patient_num in (select patient_num from #fource_misc)
-- Add death dates for other patients
insert into #fource_death
	select patient_num, isnull(death_date,'1/1/1900') 
	from dbo.patient_dimension
	where (death_date is not null or vital_status_cd in ('Y'))
		and patient_num not in (select patient_num from #fource_cohort_patients)
		and death_date >= '1/1/2016'
		and patient_num in (select patient_num from #fource_misc)
-- Define the cohorts
;with t as (
	select '1/1/2017' start_date, isnull(source_data_updated_date,GetDate()) end_date
	from #fource_config
)
insert into #fource_cohort_config
	select 'OtherMISCAdm', 1, 1, end_date, start_date, end_date from t
	union all
	select 'OtherMISCNotAdm', 1, 1, end_date, start_date, end_date from t
-- Get all MISC patients who were admitted
insert into #fource_cohort_patients
	select c.cohort, a.patient_num, min(a.admission_date), c.source_data_updated_date, 0, null, null
	from #fource_admissions a
		inner join #fource_cohort_config c
			on a.admission_date >= c.earliest_adm_date and a.admission_date <= c.latest_adm_date
	where c.cohort='OtherMISCAdm'
		and a.patient_num not in (select patient_num from #fource_cohort_patients)
		and a.patient_num in (select patient_num from #fource_misc)
	group by c.cohort, a.patient_num, c.source_data_updated_date
-- Get all other MISC patients who have an encounter
insert into #fource_cohort_patients
	select c.cohort, v.patient_num, min(v.start_date), c.source_data_updated_date, 0, null, null
	from dbo.visit_dimension v
		inner join #fource_cohort_config c
			on v.start_date >= c.earliest_adm_date and v.start_date <= c.latest_adm_date
	where c.cohort='OtherMISCNotAdm'
		and v.patient_num not in (select patient_num from #fource_cohort_patients)
		and v.patient_num in (select patient_num from #fource_misc)
	group by c.cohort, v.patient_num, c.source_data_updated_date
