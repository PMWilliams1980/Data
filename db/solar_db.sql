create schema if not exists raw;

create extension if not exists postgis;

drop table if exists raw.osm;
create table raw.osm (
  objtype varchar(8),
  osm_id bigint,
  username varchar(60),
  time_created date,
  latitude float,
  longitude float,
  area float,
  capacity float,
  modules float,
  located varchar(20),
  orientation varchar(10),
  plantref varchar(20),
  tag_power varchar(15),
  repd_id_str varchar(20),
  tag_start_date date,
  primary key (osm_id)
);

drop table if exists repd;
create table repd (
  old_repd_id varchar(15),
  repd_id integer,
  record_last_updated date,
  operator varchar(100),
  site_name varchar(100),
  tech_type varchar(40),
  storage_type varchar(40),
  co_location_repd_id float, -- can't make this int as csv contains NaN, but this is fixed below
  capacity varchar(8),
  chp_enabled varchar(3),
  ro_banding varchar(10),
  fit_tariff float,
  cfd_capacity varchar(10),
  turbine_capacity varchar(10),
  num_turbines varchar(10),
  height_turbines varchar(10),
  mounting_type varchar(10),
  dev_status varchar(40),
  dev_status_short varchar(30),
  address varchar(300),
  county varchar(30),
  region varchar(20),
  country varchar (20),
  postcode varchar(15),
  x float,
  y float,
  planning_authority varchar(70),
  planning_application_reference varchar(50),
  appeal_reference varchar(50),
  sec_state_ref varchar(50),
  type_sec_state_intervention varchar(20),
  judicial_review float,
  offshore_wind_round varchar(10),
  planning_application_submitted date,
  planning_application_withdrawn date,
  planning_permission_refused date,
  appeal_lodged date,
  appeal_withdrawn date,
  appeal_refused date,
  appeal_granted date,
  planning_permission_granted date,
  sec_state_intervened date,
  sec_state_refused date,
  sec_state_granted date,
  planning_permission_expired date,
  under_construction date,
  operational date,
  latitude float,
  longitude float,
  primary key (repd_id)
);

drop table if exists machine_vision;
create table machine_vision (
  area float,
  confidence char(1),
  install_date varchar(30), -- problem is that some of them don't have proper dates e.g. "<2016-06" and some have multiple separated by comma
  iso_code_short char(2),
  iso_code char(6),
  attribution varchar(50),
  longitude float,
  latitude float,
  primary key (latitude, longitude)
);

drop table if exists fit;
create table fit (
  row_id int,
  extension char(1),
  postcode_stub varchar(7),
  technology varchar(24),
  installed_capacity float,
  declared_net_capacity float,
  application_date date,
  commissioning_date date,
  mcs_issue_date date,
  export_status varchar(30),
  tariff_code varchar(20),
  tariff_description varchar(100),
  installation_type varchar(25),
  country varchar(15),
  local_authority varchar(40),
  govt_office_region varchar(40),
  constituency varchar(60),
  accreditation_route varchar(6),
  mpan_prefix float,
  comm_school varchar(40),
  llsoa_code varchar(20)
);

-- Upload data
-- The subdir data/raw/ should be a symbolic link to the actual data on the shared space
\copy repd from 'data/processed/repd-2019-09.csv' delimiter ',' csv header;
\copy raw.osm from 'data/processed/osm.csv' delimiter ',' csv header;
-- \copy machine_vision from 'data/raw/machine_vision.csv' delimiter ',' csv header;
\copy fit from 'data/processed/fit-2019-09.csv' delimiter ',' csv header;

-- Change floats to ints
alter table repd
alter column co_location_repd_id type int using co_location_repd_id::integer;

-- Create table that has each repd_id that an osm_id has

drop table if exists osm_repd_id_mapping;
select raw.osm.osm_id, x.repd_id
into osm_repd_id_mapping
from raw.osm, unnest(string_to_array(repd_id_str, ';')) with ordinality as x(repd_id)
order by raw.osm.osm_id, x.repd_id;
alter table osm_repd_id_mapping
alter column repd_id type int using repd_id::integer;

-- Create geometry columns for geographical comparison/matching

alter table raw.osm add column location geometry(Point, 4326);
update raw.osm set location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326);

alter table repd add column location geometry(Point, 4326);
update repd set location = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326);

-- Create de-duplicated osm table

drop table if exists osm_plantref_mapping;
select
  osm_id,
  (string_to_array(plantref, '/'))[2] as master_osm_id
into osm_plantref_mapping
from solar.osm;

alter table osm_plantref_mapping
alter column master_osm_id type bigint using master_osm_id::bigint;

drop table if exists osm;
select
  raw.osm.objtype,
  raw.osm.osm_id,
  raw.osm.username,
  raw.osm.time_created,
  raw.osm.latitude,
  raw.osm.longitude,
  raw.osm.area,
  raw.osm.capacity,
  raw.osm.modules,
  raw.osm.located,
  raw.osm.orientation,
  osm_plantref_mapping.master_osm_id,
  raw.osm.tag_power,
  raw.osm.repd_id_str,
  raw.osm.tag_start_date,
  raw.osm.location
into osm
from raw.osm
left join osm_plantref_mapping on osm_plantref_mapping.osm_id = raw.osm.osm_id
where osm_plantref_mapping.osm_id = osm_plantref_mapping.master_osm_id
or raw.osm.plantref is null;