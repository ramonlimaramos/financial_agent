alias FinancialAgent.Repo
alias FinancialAgent.RAG
alias FinancialAgent.Accounts

# Get the first user (you)
user = Repo.all(FinancialAgent.Accounts.User) |> List.first()

if user do
  IO.puts("Creating test data for user: #{user.email}")

  # Test email data
  emails = [
    %{
      content: "Hi team, the Q4 financial results are ready. Revenue increased by 15% compared to Q3. Net profit margin improved to 22%. This represents our best quarter yet with strong performance across all business units.",
      source: "gmail",
      source_id: "email_001",
      metadata: %{
        from: "cfo@company.com",
        subject: "Q4 Financial Results",
        date: "2024-01-15"
      }
    },
    %{
      content: "Meeting notes: Discussed budget allocation for 2024. Marketing: $500K, Engineering: $800K, Sales: $600K. Total budget: $1.9M. Board approved all departments. Expect quarterly reviews to track spending.",
      source: "gmail",
      source_id: "email_002",
      metadata: %{
        from: "ceo@company.com",
        subject: "2024 Budget Meeting Notes",
        date: "2024-01-10"
      }
    },
    %{
      content: "Action items from client meeting: 1. Prepare proposal by Friday 2. Schedule follow-up call next week 3. Send pricing breakdown for enterprise plan. Client expressed strong interest in our premium features.",
      source: "gmail",
      source_id: "email_003",
      metadata: %{
        from: "sarah.johnson@clientcompany.com",
        subject: "Follow-up: Project Discussion",
        date: "2024-01-12"
      }
    },
    %{
      content: "Reminder: The annual company retreat is scheduled for February 15-17 in Lake Tahoe. Please RSVP by January 30th. Activities include team building, strategic planning sessions, and outdoor recreation.",
      source: "gmail",
      source_id: "email_004",
      metadata: %{
        from: "hr@company.com",
        subject: "Annual Company Retreat - RSVP Required",
        date: "2024-01-08"
      }
    },
    %{
      content: "Product roadmap update: Q1 priorities include mobile app launch, API v2 release, and dashboard redesign. Engineering team is on track for all deliverables. Beta testing starts next month.",
      source: "gmail",
      source_id: "email_005",
      metadata: %{
        from: "product@company.com",
        subject: "Q1 Product Roadmap Update",
        date: "2024-01-11"
      }
    }
  ]

  # Test calendar data
  calendar_events = [
    %{
      content: "Team standup meeting every Monday at 9 AM. Discuss weekly goals, blockers, and priorities. Duration: 30 minutes. All team members required to attend.",
      source: "google_calendar",
      source_id: "cal_001",
      metadata: %{
        title: "Weekly Team Standup",
        date: "2024-01-15",
        attendees: ["team@company.com"]
      }
    },
    %{
      content: "Client presentation scheduled for January 20th at 2 PM. Present Q4 results and 2024 roadmap. Attendees: Client stakeholders, sales team, executive leadership. Location: Conference Room A.",
      source: "google_calendar",
      source_id: "cal_002",
      metadata: %{
        title: "Client Quarterly Review",
        date: "2024-01-20",
        attendees: ["client@company.com", "sales@company.com"]
      }
    },
    %{
      content: "Board meeting on January 25th at 10 AM. Agenda: Financial review, strategic planning, new hire approvals. Prepare slides on Q4 performance and 2024 projections.",
      source: "google_calendar",
      source_id: "cal_003",
      metadata: %{
        title: "Board of Directors Meeting",
        date: "2024-01-25",
        attendees: ["board@company.com"]
      }
    }
  ]

  # Test contact/CRM data
  crm_notes = [
    %{
      content: "Sarah Johnson from Acme Corp is our key contact for the enterprise deal. She's the VP of Operations and has budget authority. Very interested in our analytics features. Follow up weekly.",
      source: "hubspot",
      source_id: "contact_001",
      metadata: %{
        contact_name: "Sarah Johnson",
        company: "Acme Corp",
        title: "VP of Operations",
        deal_stage: "Negotiation"
      }
    },
    %{
      content: "John Smith at TechStart Inc. Reached out about integration capabilities. Scheduled demo for next Tuesday. Company size: 50-100 employees. Budget range: $50K-$100K annually.",
      source: "hubspot",
      source_id: "contact_002",
      metadata: %{
        contact_name: "John Smith",
        company: "TechStart Inc",
        title: "CTO",
        deal_stage: "Discovery"
      }
    }
  ]

  all_documents = emails ++ calendar_events ++ crm_notes

  IO.puts("\nIngesting #{length(all_documents)} documents...")
  IO.puts("=" <> String.duplicate("=", 60))

  # Ingest all test data
  results =
    Enum.map(all_documents, fn data ->
      title = data.metadata[:subject] || data.metadata[:title] || data.metadata[:contact_name]

      case RAG.ingest_document(
             user.id,
             data.content,
             data.source,
             data.source_id,
             data.metadata
           ) do
        {:ok, _} ->
          IO.puts("✓ [#{data.source}] #{title}")
          :ok

        {:error, reason} ->
          IO.puts("✗ [#{data.source}] #{title} - Error: #{inspect(reason)}")
          :error
      end
    end)

  success_count = Enum.count(results, &(&1 == :ok))
  error_count = Enum.count(results, &(&1 == :error))

  IO.puts("=" <> String.duplicate("=", 60))
  IO.puts("\n📊 Summary:")
  IO.puts("   Total: #{length(all_documents)} documents")
  IO.puts("   ✅ Success: #{success_count}")
  IO.puts("   ❌ Failed: #{error_count}")

  if error_count == 0 do
    IO.puts("\n🎉 All test data created successfully!")
    IO.puts("\n💡 Try asking these questions in the chat:")
    IO.puts("   • What were the Q4 financial results?")
    IO.puts("   • What's the 2024 budget allocation?")
    IO.puts("   • What meetings do I have with clients?")
    IO.puts("   • Tell me about Sarah Johnson")
    IO.puts("   • When is the team standup?")
  else
    IO.puts("\n⚠️  Some documents failed to ingest. Check errors above.")
  end
else
  IO.puts("=" <> String.duplicate("=", 60))
  IO.puts("❌ No user found in database!")
  IO.puts("\n📝 Steps to fix:")
  IO.puts("   1. Start the Phoenix server: mix phx.server")
  IO.puts("   2. Visit http://localhost:4000")
  IO.puts("   3. Sign in with Google and HubSpot")
  IO.puts("   4. Run this script again: mix run priv/repo/seeds_test_data.exs")
  IO.puts("=" <> String.duplicate("=", 60))
end
