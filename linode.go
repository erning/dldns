package main

import (
	"context"
	"fmt"
	"net"
	"net/http"

	"github.com/linode/linodego"
	"golang.org/x/oauth2"
)

func getDomain(token string, domainID int) (string, error) {
	client := newLinodeClient(token)
	domain, err := client.GetDomain(context.Background(), domainID)
	if err != nil {
		return "", err
	}
	return domain.Domain, nil
}

func updateDomainRecord(token string, domainID int, name string, ip string, ttl int) error {
	ipBytes := net.ParseIP(ip)
	if ipBytes == nil {
		return fmt.Errorf("invalid ip :%s", ip)
	}
	var ipType linodego.DomainRecordType
	if ipBytes.To4() != nil {
		ipType = linodego.RecordTypeA
	} else {
		ipType = linodego.RecordTypeAAAA
	}
	ip = ipBytes.String()

	ctx := context.Background()
	client := newLinodeClient(token)
	records, err := client.ListDomainRecords(ctx, domainID, nil)
	if err != nil {
		return err
	}

	var duplicateRecords []linodego.DomainRecord
	var conflictRecords []linodego.DomainRecord
	exactID := 0

	for _, record := range records {
		if record.Name != name {
			continue
		}
		if record.Type == ipType {
			duplicateRecords = append(duplicateRecords, record)
			if record.Target == ip && record.TTLSec == ttl {
				exactID = record.ID
			}
		}
		if record.Type == linodego.RecordTypeCNAME {
			conflictRecords = append(conflictRecords, record)
		}
	}

	// delte all conflict records
	for _, record := range conflictRecords {
		if err := client.DeleteDomainRecord(ctx, domainID, record.ID); err != nil {
			return err
		}
	}

	// create new record if empty
	if len(duplicateRecords) <= 0 {
		createRecord := linodego.DomainRecordCreateOptions{
			Type:   ipType,
			Name:   name,
			Target: ip,
			TTLSec: ttl,
		}
		_, err := client.CreateDomainRecord(ctx, domainID, createRecord)
		return err
	}

	// delete duplicate records except one for update
	var keptID int
	if exactID == 0 {
		keptID = duplicateRecords[0].ID
	} else {
		keptID = exactID
	}
	for _, record := range duplicateRecords {
		if keptID == record.ID {
			continue
		}
		if err := client.DeleteDomainRecord(ctx, domainID, record.ID); err != nil {
			return err
		}
	}

	if exactID == 0 {
		updateRecord := linodego.DomainRecordUpdateOptions{
			Name:   name,
			Target: ip,
			TTLSec: ttl,
		}
		_, err := client.UpdateDomainRecord(
			ctx, domainID, keptID, updateRecord,
		)
		return err
	}

	return nil
}

func newLinodeClient(token string) linodego.Client {
	tokenSource := oauth2.StaticTokenSource(&oauth2.Token{AccessToken: token})
	oauth2Client := &http.Client{
		Transport: &oauth2.Transport{
			Source: tokenSource,
		},
	}
	client := linodego.NewClient(oauth2Client)
	// client.SetDebug(true)

	return client
}
