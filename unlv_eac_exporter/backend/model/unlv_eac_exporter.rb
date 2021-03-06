require 'nokogiri'
require 'securerandom'

class EACSerializer < ASpaceExport::Serializer
	serializer_for :eac
	
	def _control(json, xml)
		xml.control {
		  xml.recordId "#{json.uri.gsub(/\//, ':')}"
		  
		  xml.maintenanceStatus json.create_time == json.system_mtime ? "new" : "revised"
		
		  xml.maintenanceAgency {
			xml.agencyName json.maintenanceAgency.agencyName
			if json.maintenanceAgency.agencyCode
			  xml.agencyCode json.maintenanceAgency.agencyCode
			end
		  }
		
		  xml.maintenanceHistory {

			json.events.each do |event|
			
			  xml.maintenanceEvent {
				xml.eventType event.type
				xml.eventDateTime(:standardDateTime => event.date_time) {
				  xml.text event.date_time
				} 
				event.agents.each do |agent|
				  xml.agentType agent[0]
				  xml.agent agent[1]
				end
			  }
			end
			}
		
		} 
    end 
	def _cpfdesc(json, xml)
    xml.cpfDescription {
      
      xml.identity {
		
        entity_type = json.jsonmodel_type.sub(/^agent_/, "").sub('corporate_entity', 'corporateBody')
        
        xml.entityType entity_type

        if json.names.length > 1
          xml.nameEntryParallel {
            _build_name_entries(json, xml)
          }
        elsif json.names
          _build_name_entries(json, xml)
        end
      }

      xml.description {
        if json.dates_of_existence[0]
          date = json.dates_of_existence[0]
          xml.existDates(:localType =>  date['certainty']) {            
            _build_date_ranges(date, xml)

          }
        end
		
        json.notes.reject {|n| n['jsonmodel_type'] != 'note_bioghist'}.each do |n|
          next unless n['publish']
          xml.biogHist {
            n['subnotes'].each do |sn|
              case sn['jsonmodel_type']
			  when 'note_text'
				xml.p {
                  xml.text sn['content']
				}
              when 'note_abstract'
                xml.abstract {
                  xml.text sn['content'].join('--')
                }
              when 'note_citation'
					
				atts = (sn['xlink'].nil?) ? {} : Hash[ sn['xlink'].map {|x, v| ["xlink:#{x}", v] }.reject{|a| a[1].nil?} ] 
				xml.citation(atts) {
				  xml.text sn['content'].join('--')
				}
              when 'note_definedlist'
                xml.list(:localType => "defined:#{sn['title']}") {
                  sn['items'].each do |item|
                    xml.item(:localType => item['label']) {
                      xml.text item['value']
                    }
                  end
                }
              when 'note_orderedlist'
                xml.list(:localType => "ordered:#{sn['title']}") {
                  sn['items'].each do |item|
                    xml.item(:localType => sn['enumeration']) {
                      xml.text item
                    }
                  end
                }
              when 'note_chronology'
                atts = sn['title'] ? {:localType => sn['title']} : {} 
                xml.chronList(atts) {
                  sn['items'].map {|i| i['events'].map {|e| [i['event_date'], e] } }.flatten(1).each do |pair|
                    date, event = pair
					date_formatted = Date.parse date rescue nil
					atts = (date.nil? || date.empty?) ? {} : {:standardDate => date }
                    xml.chronItem {
					  xml.date(atts) { xml.text date_formatted.nil? ? date : date_formatted.strftime('%d %B, %Y')  }
                      xml.event event
                    }
                  end
                }
              when 'note_outline'
                xml.outline {
                  sn['levels'].each do |level|
                    _expand_level(level, xml)
                  end
                }
              end
            end
          }
        end
      }
      
      xml.relations {

        json.related_agents.each do |related_agent|

          resolved = related_agent['_resolved']
          relator = related_agent['relator']

          name = case resolved['jsonmodel_type']
                 when 'agent_software'
                   resolved['display_name']['software_name']
                 when 'agent_family'
                   resolved['display_name']['family_name']
                 else
                   resolved['display_name']['sort_name']
                 end
		  description = related_agent['description']
		  #dates_of_existence = resolved['dates_of_existence']['expression']	 
		  #use_dates = resolved['use_dates']['expression']

          xml.cpfRelation(:cpfRelationType => relator, 'xlink:type' => 'simple', 'xlink:href' => resolved['uri']) {
            xml.relationEntry name
			xml.descriptiveNote description
          }
        end


        json.related_records.each do |record|
          role = record[:role] + "Of"
          record = record[:record]
          atts = {:resourceRelationType => role, "xlink:type" => "simple", 'xlink:href' => "#{AppConfig[:public_proxy_url]}#{record['uri']}"}
          xml.resourceRelation(atts) {
            xml.relationEntry record['title']
          }
        end


        json.external_documents.each do |document|
          next unless document['location'] =~ /^http[s]?:\/\/.+/
          atts = {:resourceRelationType => 'other', "xlink:type" => "simple", 'xlink:href' => "#{document['location']}"}
		  xml.resourceRelation(atts) {
            xml.relationEntry document['title']
          }
        end
      }
    }
  end	
 def _build_name_entries(json, xml)
    json.names.each do |name|
	  xml.entityId name['authority_id'] if name ['authority_id']
      xml.nameEntry {
        xml.authorizedForm name['rules'] if name['rules']
        xml.authorizedForm name['source'] if name['source']

        json.name_part_fields.each do |field, localType|
          localType = localType.nil? ? field : localType
          next unless name[field]
          xml.part(:localType => localType) {
            xml.text name[field]
          }
        end

        name['use_dates'].each do |date|
          xml.useDates {
            _build_date_ranges(date, xml)
          }
        end
      }
    end
  end
end