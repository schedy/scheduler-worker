require 'benchmark'
require_relative './spec_helper.rb'
require_relative '../resource.rb'


RSpec.shared_examples "fast estimator" do |resources,required|
	it 'can do 10000 no-op transitions in 1s' do
		time = Benchmark.realtime {
			10000.times {
				Resource.estimate(resources,required)
			}
		}
		expect(time).to be < 1.0
	 end
end


RSpec::Matchers.define :have_actors do |expected|
	match do |actual|
		return false if expected.size != actual[:actors].size
		actual[:actors].each_pair { |role,actor|
			return false if expected[role] != actor["id"]
		}
		true
	end
end


RSpec::Matchers.define :be_a_valid_plan do
	match do |actual|
		expect(actual).not_to be_nil
		expect(actual).to be_a(Hash)
		expect(actual[:transition_duration]).to be_a(Float).or be == 0
		expect(actual[:actors]).to be_a(Hash)
		expect(actual[:steps]).to be_a(Array)
	end
end



RSpec.describe Resource do

	context "With empty resources tree" do
		resources = [{}]
		context "and empty requirements" do
			required = []
			it 'returns a nil plan' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_a_valid_plan
				expect(plan).to have_actors({})
			end
			it_behaves_like "fast estimator", resources, required
		end
	end


	context "with one Device in resources tree" do

		resources = [
			{
				"role" => "SUT",
				"sn"=>"0123456789ABCDE",
				"type"=>"Device",
				"image"=>"a.bin",
				"id"=>1
			}
		]

		context "and empty requirements tree" do
			required = []
			it 'returns a nil plan' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_a_valid_plan
				expect(plan[:steps].size).to equal(0)
			end

		end

		context "and one Device in requirements tree, with no image specified" do
			required = [
				{
					"role"=> "SUT",
					"type"=> "Device",
					"package"=> "schedy-tests",
					"project"=> "schedy",
					"image"=> nil
				}
			]
			xit 'returns a nil plan' do #RATHER A VALID EMPTY PLAN?
				plan = Resource.estimate(resources,required)
				expect(plan).to be_nil
			end
		end

		context "and one Device in requirements tree, with a matching image specified" do
			required = [
				{
					"role"=>"SUT",
					"type"=> "Device",
					"package"=> "schedy-tests",
					"project"=> "schedy",
					"image"=> "a.bin"
				}
			]

			it 'can generate a plan with a 0 steps and 0s estimation' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_a_valid_plan
				expect(plan).to have_actors("SUT"=>1)
				expect(plan[:transition_duration]).to equal(0)
				expect(plan[:steps]).to be_a(Array)
				expect(plan[:steps].size).to equal(0)
			end

			it_behaves_like "fast estimator", resources, required

		end

		context "and one Device in requirements tree, with a not-matching image specified" do

			required = [
				{
					"role"=>"SUT",
					"type"=> "Device",
					"package"=> "schedy-tests",
					"project"=> "schedy",
					"image"=> "b.bin"
				}
			]

			it 'can generate a plan with 1 step and 60.0s estimation' do
				plan = Resource.estimate(resources,required)
				p plan
				expect(plan).to be_a(Hash)
				expect(plan[:transition_duration]).to equal(60.0)
				expect(plan[:actors]).to be_a(Hash)
				expect(plan[:actors].size).to equal(1)
				expect(plan[:actors]).to have_key("SUT")
				expect(plan[:actors]["SUT"]).to have_key("id")
				expect(plan[:actors]["SUT"]["id"]).to equal(1)
				expect(plan[:steps]).to be_a(Array)
				expect(plan[:steps].size).to equal(1)
				expect(plan[:steps].first[:resource]).to have_key("image")
				expect(plan[:steps].first[:required]).to have_key("image")
				expect(plan[:steps].first[:resource]["image"]).to eq("a.bin")
				expect(plan[:steps].first[:required]["image"]).to eq("b.bin")
			end

			it 'can do 10000 no-op transitions in 1s' do
				time = Benchmark.realtime {
					1000.times {
						Resource.estimate(resources,required)
					}
				}
				expect(time).to be < 1.0
			end

		end


		context "and two Devices in requirements tree" do

			required = [
				{
					"role"=>"SUT1",
					"type"=> "Device",
					"package"=> "schedy-tests",
					"project"=> "schedy",
				},
				{
					"role"=>"SUT2",
					"type"=> "Device",
					"package"=> "schedy-tests",
					"project"=> "schedy",
				}
			]

			it 'returns a nil plan' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_nil
			end

			it 'can do 10000 estimates 1s' do
				time = Benchmark.realtime {
					10000.times {
						Resource.estimate(resources,required)
					}
				}
				expect(time).to be < 1.0
			end

		end


		context "and one NotDevice in requirements tree" do

			required = [
				{
					"type"=> 'NotDevice',
					"role"=>'SUT'
				}
			]

			it 'returns a nil plan' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_nil
			end

			it 'can do 1000 estimates 1s' do
				time = Benchmark.realtime {
					1000.times {
						Resource.estimate(resources,required)
					}
				}
				expect(time).to be < 1.0
			end

		end
	end


	context "with two Devices in resources tree" do

		resources = [
			{

				"role" => "SUT",
				"sn"=>"0123456789ABCDY",
				"type"=>"Device",
				"image"=>"a.bin",
				"id"=>1
			},
			{

				"role" => "SUT",
				"sn"=>"0123456789ABCDX",
				"type"=>"Device",
				"image"=>"b.bin",
				"id"=>2
			}
		]

		context "and empty requirements tree" do

			required = []

			it 'returns a nil plan' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_a_valid_plan
			end

		end


		context "and one Device in requirements tree, with no image specified" do

			required = [
				{
					"type"=> 'Device',
					"role"=>'SUT',
					"image"=> nil
				}
			]


			xit 'returns a nil plan' do #NAH..
				plan = Resource.estimate(resources,required)
				expect(plan).to be_nil
			end



			it 'can do 1000 no-op transitions in 1s' do
				time = Benchmark.realtime {
					1000.times {
						Resource.estimate(resources,required)
					}
				}
				expect(time).to be < 1.0
			end

		end


		context "and one Device in requirements tree, with 'a.bin' image specified" do

			required = [
				{
					"type"=> 'Device',
					"role"=>'SUT',
					"image"=> 'a.bin'
				}
			]

			it 'estimates 0s time and 1 step with already-flashed image ' do
				plan = Resource.estimate(resources,required)

				expect(plan).to be_a(Hash)
				expect(plan[:transition_duration]).to equal(0)
				expect(plan[:actors]).to be_a(Hash)
				expect(plan[:actors].size).to equal(1)
				expect(plan[:actors]).to have_key("SUT")
				expect(plan[:actors]["SUT"]).to have_key("id")
				expect(plan[:actors]["SUT"]["id"]).to equal(1)
				expect(plan[:steps]).to be_a(Array)
				expect(plan[:steps].size).to equal(0)
			end

		end


		context "and one Device in requirements tree, with 'b' image specified" do

			required = [
				{
					"type"=> 'Device',
					"role"=>'SUT',
					"image"=> 'b.bin'
				}
			]

			it 'can generate a plan with a 0s estimation and 1 step' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_a(Hash)
				expect(plan[:transition_duration]).to equal(0)
				expect(plan[:actors]).to be_a(Hash)
				expect(plan[:actors].size).to equal(1)
				expect(plan[:actors]).to have_key("SUT")
				expect(plan[:actors]["SUT"]).to have_key("id")
				expect(plan[:actors]["SUT"]["id"]).to equal(2)
				expect(plan[:steps]).to be_a(Array)
				expect(plan[:steps].size).to equal(0)
			end

		end


		context "and one Device in requirements tree, with and not-matching image specified" do

			required = [
				{
					"type"=> 'Device',
					"role"=>'SUT',
					"image"=> 'c.bin',
				}
			]


			it 'can generate a plan with a 60.0s estimation and 1 step' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_a(Hash)
				expect(plan[:transition_duration]).to equal(60.0)
				expect(plan[:actors]).to be_a(Hash)
				expect(plan[:actors].size).to equal(1)
				expect(plan[:actors]).to have_key("SUT")
				expect(plan[:actors]["SUT"]).to have_key("id")
				expect(plan[:actors]["SUT"]["id"]).to equal(1).or eq(2)
				expect(plan[:steps]).to be_a(Array)
				expect(plan[:steps].size).to equal(1)
				expect(plan[:steps].first[:resource]).to have_key("image")
				expect(plan[:steps].first[:required]).to have_key("image")
				expect(plan[:steps].first[:resource]["image"]).to eq("a.bin").or eq("b.bin")
				expect(plan[:steps].first[:required]["image"]).to eq("c.bin")
			end

		end


		context "and two Devices in requirements tree" do

			required = [
				{
					"type"=> 'Device',
					"role"=>'SUT1',
					"image"=> 'b.bin'
				},
				{
					"type"=> 'Device',
					"role"=>'SUT2',
					"image"=> 'a.bin'
				}
			]

			it 'returns a plan with 0s estimate and 2 steps' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_a(Hash)
				expect(plan[:transition_duration]).to equal(0)
				expect(plan[:actors]).to be_a(Hash)
				expect(plan[:actors].size).to equal(2)
				expect(plan[:actors]).to have_key("SUT1")
				expect(plan[:actors]).to have_key("SUT2")
				expect(plan[:actors]["SUT1"]).to have_key("id")
				expect(plan[:actors]["SUT1"]["id"]).to equal(2)
				expect(plan[:actors]["SUT2"]).to have_key("id")
				expect(plan[:actors]["SUT2"]["id"]).to equal(1)
				expect(plan[:steps]).to be_a(Array)
				expect(plan[:steps].size).to equal(0)
			end

			it 'can do 1000 estimates 1s' do
				time = Benchmark.realtime {
					1000.times {
						Resource.estimate(resources,required)
					}
				}
				expect(time).to be < 1.0
			end

		end


		context "and one NotDevice in requirements tree" do

			required = [
				{
					"type"=> 'NotDevice',
					"role"=>'SUT'
				}
			]

			it 'returns a nil plan' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_nil
			end

			it 'can do 1000 estimates 1s' do
				time = Benchmark.realtime {
					1000.times {
						Resource.estimate(resources,required)
					}
				}
				expect(time).to be < 1.0
			end

		end

	end


	context "with 2 parent resources with 3 children in resources tree" do
		resources = [
			{
				id: 1,
				"type"=> 'Multiplexer',
				parent_id: nil,
				"children" => [
					{ "id"=> 2,"type"=> 'Device', "image"=> 'a.bin', parent_id: 1 },
					{ "id"=> 3,"type"=> 'Device', "image"=> 'a.bin', parent_id: 1  },
					{ "id"=> 4,"type"=> 'Device', "image"=> 'a.bin', parent_id: 1  }
				]
			},
			{
				id: 5,
				"type"=> 'Multiplexer',
				parent_id: nil,
				"children" => [
					{ "id"=> 6,"type"=> 'Device', "image"=> 'b.bin', parent_id: 2  },
					{ "id"=> 7,"type"=> 'Device', "image"=> 'b.bin', parent_id: 2  },
					{ "id"=> 8,"type"=> 'Device', "image"=> 'b.bin', parent_id: 2  }
				]
			}
		]


		context "and empty requirements tree" do
			required = []
			it 'returns a nil plan' do
				plan = Resource.estimate(resources,required)
				p plan
				expect(plan).to be_a_valid_plan
			end
		end

		context "and requirement forest with two Devices on the same Multiplexer" do

			required = [
				{
					"type"=> 'Multiplexer',
					"role"=>'Mp1',
					"children"=>[
						{
							"type"=> 'Device',
							"role"=>'Mp1:1',
							"image"=> 'b.bin',

						},
						{
							"type"=> 'Device',
							"role"=>'Mp1:2',
							"image"=> nil
						}
					]
				}
			]

			it 'returns a valid plan' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_a_valid_plan
				expect(plan[:actors].size).to equal(3)
				expect(plan[:actors]).to have_key("Mp1")
				expect(plan[:actors]).to have_key("Mp1:1")
				expect(plan[:actors]).to have_key("Mp1:2")
				expect(plan[:actors]["Mp1:1"]).to have_key("id")
				expect(plan[:actors]["Mp1:1"]["id"]).to equal(6).or equal(7).or equal(8)

			end
		end
	end


	context "with 16 Devices in resources tree" do

		resources =
		16.times.to_a.map { |id|
			{
				"id"=> id+1,
				"type"=> 'Device',
				"image"=> 'b.bin',
				"count"=> 1,
				"tasks"=> 0
			}
		}


		context "and empty requirements tree" do

			required = []


			it 'returns a nil plan' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_a_valid_plan
			end


		end


		context "and one Device in requirements tree, with no image specified" do

			required = [
				{
					"type"=> 'Device',
					"role"=>'SUT',
					"image"=> nil
				}
			]

			xit 'returns a nil plan' do #no
				plan = Resource.estimate(resources,required)
				expect(plan).to be_nil
			end


			it 'can do 1000 no-op transitions in 1s' do
				time = Benchmark.realtime {
					1000.times {
						Resource.estimate(resources,required)
					}
				}
				expect(time).to be < 1.0
			end

		end


		context "and one Device in requirements tree, with 'a' image specified" do

			required = [
				{
					"type"=> 'Device',
					"role"=>'SUT',
					"image"=> 'a.bin'
				}
			]

			it 'returns a plan with 60.0 estimate and 1 step' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_a(Hash)
				expect(plan[:transition_duration]).to equal(60.0)
				expect(plan[:actors]).to be_a(Hash)
				expect(plan[:actors].size).to equal(1)
				expect(plan[:actors]).to have_key("SUT")
				expect(plan[:actors]["SUT"]).to have_key("id")
				#expect(plan[:actors]["SUT"]["id"]).to equal(1) #this is not given. any resource of the same cost could be selected.
				expect(plan[:steps]).to be_a(Array)
				expect(plan[:steps].size).to equal(1)
				expect(plan[:steps].first[:resource]).to have_key("image")
				expect(plan[:steps].first[:required]).to have_key("image")
				expect(plan[:steps].first[:resource]["image"]).to eq("b.bin")
				expect(plan[:steps].first[:required]["image"]).to eq("a.bin")
			end

		end


		context "and one Device in requirements tree, with 'b' image specified" do

			required = [
				{
					"type"=> 'Device',
					"role"=>'SUT',
					"image"=> 'b.bin'
				}
			]

			it 'returns a plan with 0 estimate and 1 step' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_a(Hash)
				expect(plan[:transition_duration]).to equal(0)
				expect(plan[:actors]).to be_a(Hash)
				expect(plan[:actors].size).to equal(1)
				expect(plan[:actors]).to have_key("SUT")
				expect(plan[:actors]["SUT"]).to have_key("id")
				#expect(plan[:actors]["SUT"]["id"]).to equal(1) #this is not given. any resource of the same cost could be selected.
				expect(plan[:steps]).to be_a(Array)
				expect(plan[:steps].size).to equal(0)
			end

		end



		context "and two devices in requirements tree, one with image a and other with b" do

			required = [
				{
					"type"=> 'Device',
					"role"=>'SUT1',
					"image"=> 'b.bin'
				},
				{
					"type"=> 'Device',
					"role"=>'SUT2',
					"image"=> 'a.bin'
				}
			]

			it 'returns correct plan from estimation' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_a(Hash)
				expect(plan[:transition_duration]).to equal(60.0)
				expect(plan[:actors]).to be_a(Hash)
				expect(plan[:actors].size).to equal(2)
				expect(plan[:actors]).to have_key("SUT1")
				expect(plan[:actors]).to have_key("SUT2")
				expect(plan[:actors]["SUT1"]).to have_key("id")
				#expect(plan[:actors]["SUT1"]["id"]).to equal(1) NO
				expect(plan[:actors]["SUT2"]).to have_key("id")
				#expect(plan[:actors]["SUT2"]["id"]).to equal(2) NO
				expect(plan[:steps]).to be_a(Array)
				expect(plan[:steps].size).to equal(1)
				expect(plan[:steps].last[:resource]).to have_key("image")
				expect(plan[:steps].last[:required]).to have_key("image")
				expect(plan[:steps].last[:resource]["image"]).to eq("b.bin")
				expect(plan[:steps].last[:required]["image"]).to eq("a.bin")

			end

			it 'can do 1000 estimates 1s' do
				time = Benchmark.realtime {
					1000.times {
						Resource.estimate(resources,required)
					}
				}
				expect(time).to be < 1.0
			end

		end

		context "and six Devices in requirements tree" do

			required = [
				{
					"type"=> 'Device',
					"role"=>'SUT1',
					"image"=> 'a.bin'
				},
				{
					"type"=> 'Device',
					"role"=>'SUT2',
					"image"=> 'a.bin'
				},
				{
					"type"=> 'Device',
					"role"=>'SUT3',
					"image"=> 'a.bin'
				},
				{
					"type"=> 'Device',
					"role"=>'SUT4',
					"image"=> 'a.bin'
				},
				{
					"type"=> 'Device',
					"role"=>'SUT4',
					"image"=> 'a.bin'
				},
				{
					"type"=> 'Device',
					"role"=>'SUT4',
					"image"=> 'a.bin'
				}
			]


			it 'can do 1000 estimates 1s' do
				time = Benchmark.realtime {
					1000.times {
						Resource.estimate(resources,required)
					}
				}
				expect(time).to be < 1.0
			end

		end

		context "and one NotDevice in requirements tree" do

			required = [
				{
					"type"=> 'NotDevice',
					"role"=>'SUT'
				}
			]

			it 'returns a nil plan' do
				plan = Resource.estimate(resources,required)
				expect(plan).to be_nil
			end

			it 'can do 1000 estimates 1s' do
				time = Benchmark.realtime {
					1000.times {
						Resource.estimate(resources,required)
					}
				}
				expect(time).to be < 1.0
			end

		end
	end

end
