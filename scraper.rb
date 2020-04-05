#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'json'
require 'nokogiri'
require 'open-uri'
require 'pry'
require 'scraped'
require 'scraperwiki'

class CantonList < Scraped::JSON
  field :cantons do
    json.map { |j| fragment j => Canton }
  end
end

class Canton < Scraped::JSON
  field :id do
    json[:abbreviation]
  end

  field :name do
    json[:name]
  end

  field :identifier__parlamentdotch do
    json[:id]
  end
end

CANTON_URL = 'http://ws-old.parlament.ch/cantons'

@cantons = CantonList.new(response: Scraped::Request.new(
  url: CANTON_URL, headers: { 'Accept' => 'text/json' }
).response).cantons.map { |c| [c.id, c.to_h] }.to_h

def json_from(url)
  JSON.parse(open(url, 'Accept' => 'text/json').read, symbolize_names: true)
end

def gender_from(str)
  return unless str
  return 'male' if str == 'm'
  return 'female' if str == 'f'
  raise "unknown gender: #{str}"
end

def scrape_term(t)
  return if t[:id] > 51 # or if the term start date is in the future
  base = "http://ws-old.parlament.ch/councillors/historic?legislativePeriodFromFilter=#{t[:id]}&format=json&pageNumber=%d"

  page = 0
  while page += 1
    url = base % page
    mems = json_from(url)
    mems.each do |mem|
      scrape_person(mem, t)
    end
    break unless mems.last[:hasMorePages]
  end
end

def scrape_person(mp, term)
  # This is icky, but it'll do until we rewrite the whole thing using Scraped
  canton = @cantons[mp[:canton][:abbreviation]] or raise("Unknown canton: #{mp[:canton]}")

  data = {
    id:                         mp[:id],
    identifier__parlamentdotch: mp[:id],
    name:                       mp[:firstName] + ' ' + mp[:lastName],
    sort_name:                  mp[:lastName] + ', ' + mp[:firstName],
    given_name:                 mp[:firstName],
    family_name:                mp[:lastName],
    birth_date:                 mp[:birthDate].slice!(0, 10),
    gender:                     gender_from(mp[:gender]),
    area:                       canton[:name],
    area_id:                    canton[:id],
    council:                    mp[:council][:abbreviation],
    council_id:                 mp[:council][:id],
    party:                      mp[:party][:abbreviation],
    party_id:                   mp[:party][:id],
    faction:                    mp[:faction][:abbreviation],
    faction_id:                 mp[:faction][:id],
    term:                       term[:id],
    source:                     "https://www.parlament.ch/en/biografie?CouncillorId=#{mp[:id]}",
  }

  if mp[:membership][:entryDate]
    start_date = mp[:membership][:entryDate].slice(0, 10)
    data[:start_date] = start_date if start_date > term[:start_date]
  end

  if mp[:membership][:leavingDate]
    end_date = mp[:membership][:leavingDate].slice(0, 10)
    data[:end_date] = end_date if end_date < term[:end_date]
  end

  ScraperWiki.save_sqlite(%i(id term), data)
end

terms = json_from('http://ws-old.parlament.ch/legislativeperiods?format=json')

terms.each do |t|
  t[:start_date] = (t.delete :from).slice!(0, 10)
  t[:end_date] = (t.delete :to).slice!(0, 10)
  %i(hasMorePages updated code).each { |i| t.delete i }
  t.delete :hasMorePages
  t.delete :updated
  puts t
  ScraperWiki.save_sqlite([:id], t, 'terms')
  scrape_term(t)
end
