#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'nokogiri'
require 'open-uri'
require 'colorize'
require 'json'

require 'pry'

def json_from(url)
  JSON.parse(open(url, "Accept" => "text/json").read, symbolize_names: true)
end

def gender_from(str)
  return unless str
  return 'male' if str == 'm'
  return 'female' if str == 'f'
  raise "unknown gender: #{str}"
end

def scrape_term(t)
  if t[:id] == 50 
    base = "http://ws.parlament.ch/councillors/basicdetails?format=json&pageNumber=%d"
  else
    base = "http://ws.parlament.ch/councillors/historic?legislativePeriodFromFilter=#{t[:id]}&format=json&pageNumber=%d" 
  end

  page = 0
  while page += 1
    url = base % page
    mems = json_from(url)

    mems.each do |mem|
      t[:id] == 50 ?  scrape_current(mem, t) : scrape_person(mem, t)
    end
    break unless mems.last[:hasMorePages]
  end
end

# Sigh
def scrape_current(mp, term)
  data = { 
    id: mp[:id],
    name: mp[:firstName] + " " + mp[:lastName],
    sort_name: mp[:lastName] + ", " + mp[:firstName],
    given_name: mp[:firstName],
    family_name: mp[:lastName],
    area: mp[:canton],
    council: mp[:council],
    party: mp[:party],
    faction: mp[:faction],
    image: mp[:pictureUrl],
    term: term[:id],
    source: mp[:biographyUrl],
  }
  ScraperWiki.save_sqlite([:id, :term], data)
end

def scrape_person(mp, term)
  data = { 
    id: mp[:id],
    name: mp[:firstName] + " " + mp[:lastName],
    sort_name: mp[:lastName] + ", " + mp[:firstName],
    given_name: mp[:firstName],
    family_name: mp[:lastName],
    birth_date: mp[:birthDate].slice!(0,10),
    gender: gender_from(mp[:gender]),
    area: mp[:canton][:abbreviation],
    council: mp[:council][:abbreviation],
    council_id: mp[:council][:id],
    party: mp[:faction][:abbreviation],
    faction: mp[:faction][:abbreviation],
    term: term[:id],
  }

  if mp[:membership][:entryDate]
    start_date = mp[:membership][:entryDate].slice(0,10) 
    data[:start_date] = start_date if start_date > term[:start_date]
  end

  if mp[:membership][:leavingDate]
    end_date = mp[:membership][:leavingDate].slice(0,10) 
    data[:start_date] = end_date if end_date < term[:end_date]
  end

  ScraperWiki.save_sqlite([:id, :term], data)
end



terms = json_from('http://ws.parlament.ch/legislativeperiods?format=json')

terms.each do |t|
  t[:start_date] = t.delete :from
  t[:end_date] = t.delete :to
  %i(hasMorePages updated code).each { |i| t.delete i }
  t.delete :hasMorePages
  t.delete :updated
  puts t
  ScraperWiki.save_sqlite([:id], t, 'terms')
  scrape_term(t)
end

