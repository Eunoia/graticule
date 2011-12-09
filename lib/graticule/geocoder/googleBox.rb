# encoding: UTF-8
module Graticule #:nodoc:
  module Geocoder #:nodoc:

    # First you need a Google Maps API key.  You can register for one here:
    # http://www.google.com/apis/maps/signup.html
    #
    #   gg = Graticule.service(:google).new(MAPS_API_KEY)
    #   location = gg.locate '1600 Amphitheater Pkwy, Mountain View, CA'
    #   p location.coordinates
    #   #=> [37.423111, -122.081783
    #
    class GoogleBox < Base
      # http://www.google.com/apis/maps/documentation/#Geocoding_HTTP_Request

      # http://www.google.com/apis/maps/documentation/reference.html#GGeoAddressAccuracy
      PRECISION = {
        0 => Precision::Unknown,      # Unknown location.
        1 => Precision::Country,      # Country level accuracy.
        2 => Precision::Region,       # Region (state, province, prefecture, etc.) level accuracy.
        3 => Precision::Region,       # Sub-region (county, municipality, etc.) level accuracy.
        4 => Precision::Locality,     # Town (city, village) level accuracy.
        5 => Precision::PostalCode,   # Post code (zip code) level accuracy.
        6 => Precision::Street,       # Street level accuracy.
        7 => Precision::Street,       # Intersection level accuracy.
        8 => Precision::Address,      # Address level accuracy.
        9 => Precision::Premise       # Premise (building name, property name, shopping center, etc.) level accuracy.
      }

      def initialize(box={})
		  #This api is using v2. Google has depricated it, and recomends using v3.
		  #In version three, a bounding box is the sw and nw corners. 
		  #In v2, it's the center and the span of the bounding box. 
		  #Box is going to be a bounding box, but it will be converted into a center and span
		  @box = if(box.empty?)
							  ""
					elsif box.is_a? String
							  box
					else
							  box[:sw][:lat]+","+box[:sw][:lng]+"|"+box[:ne][:lat]+","+box[:ne][:lng]
					end
		  corners = @box.split("|")
		  centerLat  = (corners[0].split(",")[0].to_f + corners[1].split(",")[0].to_f )/ 2.0
		  centerLng  = (corners[0].split(",")[1].to_f + corners[1].split(",")[1].to_f)/2.0
		  @ll = centerLat.to_s + "," + centerLng.to_s
		  @spnH =  (corners[0].split(",")[0].to_f - corners[1].split(",")[0].to_f ).abs
		  @spaV = (corners[0].split(",")[1].to_f - corners[1].split(",")[1].to_f).abs
		  @spn = @spnH.to_s+","+@spaV.to_s
        @url = URI.parse 'http://maps.googleapis.com/maps/geo'
      end

      # Locates +address+ returning a Location
      def locate(address)
        get :q => address.is_a?(String) ? address : location_from_params(address).to_s
      end

    private
      class Address
        include HappyMapper
        tag 'AddressDetails'
        namespace 'urn:oasis:names:tc:ciq:xsdschema:xAL:2.0'

        attribute :accuracy, Integer, :tag => 'Accuracy'
      end

      class Placemark
        include HappyMapper
        tag 'Placemark'
        element :coordinates, String, :deep => true
        has_one :address, Address

        attr_reader :longitude, :latitude

        with_options :deep => true, :namespace => 'urn:oasis:names:tc:ciq:xsdschema:xAL:2.0' do |map|
          map.element :street,      String, :tag => 'ThoroughfareName'
          map.element :locality,    String, :tag => 'LocalityName'
          map.element :region,      String, :tag => 'AdministrativeAreaName'
          map.element :postal_code, String, :tag => 'PostalCodeNumber'
          map.element :country,     String, :tag => 'CountryNameCode'
        end

        def coordinates=(coordinates)
          @longitude, @latitude, _ = coordinates.split(',').map { |v| v.to_f }
        end

        def accuracy
          address.accuracy if address
        end

        def precision
          PRECISION[accuracy] || :unknown
        end
      end

      class Response
        include HappyMapper
        tag 'Response'
        element :code, Integer, :tag => 'code', :deep => true
        has_many :placemarks, Placemark
      end

      def prepare_response(xml)
        Response.parse(xml, :single => true)
      end

      def parse_response(response) #:nodoc:
        result = response.placemarks.first
        Location.new(
          :latitude    => result.latitude,
          :longitude   => result.longitude,
          :street      => result.street,
          :locality    => result.locality,
          :region      => result.region,
          :postal_code => result.postal_code,
          :country     => result.country,
          :precision   => result.precision
        )
      end

      # Extracts and raises an error from +xml+, if any.
      def check_error(response) #:nodoc:
        case response.code
        when 200 then # ignore, ok
        when 500 then
          raise Error, 'server error'
        when 601 then
          raise AddressError, 'missing address'
        when 602 then
          raise AddressError, 'unknown address'
        when 603 then
          raise AddressError, 'unavailable address'
        when 610 then
          raise CredentialsError, 'invalid key'
        when 620 then
          raise CredentialsError, 'too many queries'
        else
          raise Error, "unknown error #{response.code}"
        end
      end

      # Creates a URL from the Hash +params+.
      # sets the output type to 'xml'.
      def make_url(params) #:nodoc:
        super params.merge(:output => "xml", :oe => 'utf8', :ll => @ll, :spn => @spn, :sensor => false)
      end
    end
  end
end
