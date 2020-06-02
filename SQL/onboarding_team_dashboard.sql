-- This query is not related to the COVID-19 data set or analysis.
--------------------------------------------------------------------
-- I am including it here to showcase PostgreSQL skills in conjunction with Tableau and Amazon Redshift
-- The workbook runs an extract refresh every night to power a Tableau Dashboard for the onboarding team with my Company FareHarbor
-- Queries to two different databases are joined in Tableau containing data below from our CRM (Close.io, very similar to SalesForce)
-- as well as another query (not pictured) which connects to our other database with data from our SaaS platform
-- a few updates are still in the works to join the various dates in the onboarding process to a master date range, along with a few additional metrics
-- requested by the onboarding team.
WITH close_data as 
        (SELECT 
            id as lead_id, 
            custom_fh_shortname, 
			custom_lead_type_related as related,
            custom_ob_02_dashboard_builder as builder_id, 
            custom_ob_04_onboarder as onboarder_id, 
			custom_location___region as region,
			custom_account_tier as tier,
			custom_language___primary as language,
            DATE(custom_ob_build_completion_date) as build_date_completion
			FROM alooma.lead
        ),

builder as (Select id, first_name|| ' '||last_name as builder_use
						From alooma.user ), 

onboarder as (Select id, first_name|| ' '||last_name as onboarder_use
						From alooma.user),

go_live as (SELECT
			ld.lead_id,
			-- if the status update is null, then use the AM_live_Date instead to calculate 'go-live'
			CASE WHEN ld.go_live_status IS NOT NULL THEN ld.go_live_status
					WHEN ld.go_live_status IS NULL THEN ld.am_live_date
					ELSE NULL END AS go_live
			FROM
				(-- get all lead ids and the first status update to show Live Customer
					SELECT 
							a.lead_id,
							DATE(MIN(a.date_updated)) go_live_status, 
							DATE(l.custom_am___live_date) AS am_live_date
					FROM alooma.lead l
					LEFT JOIN alooma.activity a on l.id = a.lead_id
					WHERE (a._type = 'LeadStatusChange' 
								AND a.old_status_label <> 'Live Customer') 
								AND a.new_status_label = 'Live Customer'
					GROUP BY a.lead_id, l.custom_am___live_date
				) ld
			),
			
train_date as (SELECT 
                    DATE(MAX(a.date_updated)) train_date, 
                    a.lead_id
            FROM alooma.activity a
            WHERE (a._type = 'LeadStatusChange' 
                    AND a.old_status_label <> 'Trained - Wait for Live') 
                    AND a.new_status_label = 'Trained - Wait for Live'
            GROUP BY a.lead_id)			
            
SELECT 
		c.lead_id, 
		c.custom_fh_shortname, 
		f.builder_use, 
		g.onboarder_use, 
		c.build_date_completion, 
		t.train_date,
		c.tier,
		c.region,
		d.go_live,
		(d.go_live - t.train_date) AS days_to_live,
		CASE WHEN c.language = 'Spanish' THEN 1 ELSE 0 END AS spanish_count,
		CASE WHEN c.related = 'Secondary' THEN 1 ELSE 0 END AS related_lead,
		CASE WHEN d.go_live = t.train_date THEN 1 ELSE 0 END AS lsd 
FROM close_data c
LEFT JOIN builder f ON f.id=c.builder_id 
LEFT JOIN onboarder g ON g.id=c.onboarder_id
LEFT JOIN go_live d ON c.lead_id = d.lead_id
LEFT JOIN train_date t ON c.lead_id = t.lead_id
WHERE c.build_date_completion >= '2018-01-01' 
OR t.train_date >= '2018-08-01'  
ORDER BY t.train_date