defmodule TalesForge.Game.WorldSimCharacterizationTest do
  @moduledoc """
  Characterization of `WorldSim.tick/1` before round 2 PR 8: clock
  thresholds (`apply_threshold/3`) and rule events (`apply_matching_events/3`),
  the exact fronts and applied moves from main. Pure, no LLM calls.
  """
  use ExUnit.Case, async: true

  alias TalesForge.Game.WorldSim

  test "the exact fronts and applied moves for each case" do
    defn = %{
      "rules" => [
        %{"on_event" => "time.passed", "clock" => "doom", "delta" => 2},
        %{"on_event" => "player.shouted", "move" => "hire_extra"},
        %{"on_event" => "player.shouted", "move" => "unknown_front_probe"},
        %{"on_event" => "player.paid", "move" => "mark_debt"}
      ],
      "public_facts_on" => %{
        "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"},
        "bad" => "not a map"
      },
      "moves" => %{
        "hire_extra" => %{
          "wage" => 2,
          "public_fact" => %{"id" => "hired", "text" => "A new blade"}
        },
        "call_help" => %{
          "public_fact" => %{"id" => "help", "text" => "Help comes", "visibility" => ["inn"]}
        }
      }
    }

    front = fn clocks, coin ->
      %{
        front_id: "f1",
        status: "live",
        definition: defn,
        runtime_state: %{"clocks" => clocks, "resources" => %{"coin" => coin}}
      }
    end

    ev = fn kind, d -> %{"kind" => kind, "payload" => %{"delta_ticks" => d}} end

    cases = [
      {"below threshold",
       [front.(%{"doom" => %{"value" => 0, "threshold" => 10, "on_threshold" => "doom_hit"}}, 5)],
       [ev.("time.passed", 1)],
       {[
          %{
            status: "live",
            front_id: "f1",
            definition: %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            runtime_state: %{
              "clocks" => %{
                "doom" => %{"on_threshold" => "doom_hit", "threshold" => 10, "value" => 2}
              },
              "resources" => %{"coin" => 5}
            }
          }
        ], []}},
      {"crosses with two events and delta_ticks",
       [front.(%{"doom" => %{"value" => 5, "threshold" => 10, "on_threshold" => "doom_hit"}}, 5)],
       [ev.("time.passed", 2), ev.("time.passed", 0)],
       {[
          %{
            status: "live",
            front_id: "f1",
            definition: %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            runtime_state: %{
              "clocks" => %{
                "doom" => %{"on_threshold" => "doom_hit", "threshold" => 10, "value" => 11}
              },
              "public_facts" => [
                %{"id" => "doom_hit", "text" => "Doom is near", "visibility" => ["public"]}
              ],
              "resources" => %{"coin" => 5}
            }
          }
        ], []}},
      {"already over, fact present once",
       [
         front.(%{"doom" => %{"value" => 12, "threshold" => 10, "on_threshold" => "doom_hit"}}, 5)
         |> put_in([:runtime_state, "public_facts"], [%{"id" => "doom_hit", "text" => "old"}])
       ], [ev.("time.passed", 1)],
       {[
          %{
            status: "live",
            front_id: "f1",
            definition: %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            runtime_state: %{
              "clocks" => %{
                "doom" => %{"on_threshold" => "doom_hit", "threshold" => 10, "value" => 14}
              },
              "public_facts" => [%{"id" => "doom_hit", "text" => "old"}],
              "resources" => %{"coin" => 5}
            }
          }
        ], []}},
      {"no coin",
       [
         front.(%{"doom" => %{"value" => 12, "threshold" => 10, "on_threshold" => "doom_hit"}}, 0)
       ], [ev.("time.passed", 1)],
       {[
          %{
            status: "live",
            front_id: "f1",
            definition: %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            runtime_state: %{
              "clocks" => %{
                "doom" => %{"on_threshold" => "doom_hit", "threshold" => 10, "value" => 14}
              },
              "resources" => %{"coin" => 0}
            }
          }
        ], []}},
      {"coin missing",
       [
         put_in(
           front.(
             %{"doom" => %{"value" => 12, "threshold" => 10, "on_threshold" => "doom_hit"}},
             1
           ),
           [:runtime_state, "resources"],
           %{}
         )
       ], [],
       {[
          %{
            status: "live",
            front_id: "f1",
            definition: %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            runtime_state: %{
              "clocks" => %{
                "doom" => %{"on_threshold" => "doom_hit", "threshold" => 10, "value" => 12}
              },
              "resources" => %{}
            }
          }
        ], []}},
      {"fact not a map",
       [front.(%{"doom" => %{"value" => 12, "threshold" => 10, "on_threshold" => "bad"}}, 5)], [],
       {[
          %{
            status: "live",
            front_id: "f1",
            definition: %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            runtime_state: %{
              "clocks" => %{
                "doom" => %{"on_threshold" => "bad", "threshold" => 10, "value" => 12}
              },
              "resources" => %{"coin" => 5}
            }
          }
        ], []}},
      {"no on_threshold key", [front.(%{"doom" => %{"value" => 12, "threshold" => 10}}, 5)], [],
       {[
          %{
            status: "live",
            front_id: "f1",
            definition: %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            runtime_state: %{
              "clocks" => %{"doom" => %{"threshold" => 10, "value" => 12}},
              "resources" => %{"coin" => 5}
            }
          }
        ], []}},
      {"threshold not integer",
       [
         front.(
           %{"doom" => %{"value" => 12, "threshold" => "10", "on_threshold" => "doom_hit"}},
           5
         )
       ], [],
       {[
          %{
            status: "live",
            front_id: "f1",
            definition: %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            runtime_state: %{
              "clocks" => %{
                "doom" => %{"on_threshold" => "doom_hit", "threshold" => "10", "value" => 12}
              },
              "resources" => %{"coin" => 5}
            }
          }
        ], []}},
      {"clock not a map",
       [
         front.(
           %{
             "doom" => 3,
             "other" => %{"value" => 1, "threshold" => 1, "on_threshold" => "doom_hit"}
           },
           5
         )
       ], [],
       {[
          %{
            status: "live",
            front_id: "f1",
            definition: %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            runtime_state: %{
              "clocks" => %{
                "doom" => 3,
                "other" => %{"on_threshold" => "doom_hit", "threshold" => 1, "value" => 1}
              },
              "public_facts" => [
                %{"id" => "doom_hit", "text" => "Doom is near", "visibility" => ["public"]}
              ],
              "resources" => %{"coin" => 5}
            }
          }
        ], []}},
      {"moves: ok, error, then a person move", [front.(%{}, 5)],
       [%{"kind" => "player.shouted"}, %{"kind" => "player.paid"}, %{"kind" => "player.shouted"}],
       {[
          %{
            status: "live",
            front_id: "f1",
            definition: %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            runtime_state: %{
              "clocks" => %{},
              "memories" => [%{"felt" => "owed", "tick" => nil}],
              "public_facts" => [%{"id" => "hired", "text" => "A new blade", "visibility" => []}],
              "resources" => %{"coin" => 1}
            }
          }
        ],
        [
          %{id: "f1", move: "hire_extra"},
          %{id: "f1", move: "hire_extra"},
          %{id: "f1", move: "mark_debt"}
        ]}},
      {"string-keyed front",
       [
         %{
           "front_id" => "f2",
           "status" => "live",
           "definition" => defn,
           "runtime_state" => %{
             "clocks" => %{
               "doom" => %{"value" => 9, "threshold" => 10, "on_threshold" => "doom_hit"}
             },
             "resources" => %{"coin" => 2}
           }
         }
       ], [ev.("time.passed", 1)],
       {[
          %{
            "definition" => %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            "front_id" => "f2",
            "runtime_state" => %{
              "clocks" => %{
                "doom" => %{"on_threshold" => "doom_hit", "threshold" => 10, "value" => 11}
              },
              "public_facts" => [
                %{"id" => "doom_hit", "text" => "Doom is near", "visibility" => ["public"]}
              ],
              "resources" => %{"coin" => 2}
            },
            "status" => "live"
          }
        ], []}},
      {"a stage fires a pack move",
       [
         front.(
           %{
             "doom" => %{
               "value" => 8,
               "threshold" => 10,
               "on_threshold" => "doom_hit",
               "stages" => [%{"at" => 10, "move" => "call_help"}]
             }
           },
           5
         )
       ], [ev.("time.passed", 1)],
       {[
          %{
            status: "live",
            front_id: "f1",
            definition: %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            runtime_state: %{
              "clocks" => %{
                "doom" => %{
                  "on_threshold" => "doom_hit",
                  "stages" => [%{"at" => 10, "move" => "call_help"}],
                  "threshold" => 10,
                  "value" => 10
                }
              },
              "public_facts" => [
                %{"id" => "doom_hit", "text" => "Doom is near", "visibility" => ["public"]}
              ],
              "resources" => %{"coin" => 5}
            }
          }
        ], []}},
      {"hire with too little coin", [front.(%{}, 1)], [%{"kind" => "player.shouted"}],
       {[
          %{
            status: "live",
            front_id: "f1",
            definition: %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            runtime_state: %{"clocks" => %{}, "resources" => %{"coin" => 1}}
          }
        ], []}},
      {"spent front does not tick", [%{front.(%{}, 5) | status: "spent"}],
       [%{"kind" => "player.shouted"}],
       {[
          %{
            status: "spent",
            front_id: "f1",
            definition: %{
              "moves" => %{
                "call_help" => %{
                  "public_fact" => %{
                    "id" => "help",
                    "text" => "Help comes",
                    "visibility" => ["inn"]
                  }
                },
                "hire_extra" => %{
                  "public_fact" => %{"id" => "hired", "text" => "A new blade"},
                  "wage" => 2
                }
              },
              "public_facts_on" => %{
                "bad" => "not a map",
                "doom_hit" => %{"text" => "Doom is near", "visibility" => "public"}
              },
              "rules" => [
                %{"clock" => "doom", "delta" => 2, "on_event" => "time.passed"},
                %{"move" => "hire_extra", "on_event" => "player.shouted"},
                %{"move" => "unknown_front_probe", "on_event" => "player.shouted"},
                %{"move" => "mark_debt", "on_event" => "player.paid"}
              ]
            },
            runtime_state: %{"clocks" => %{}, "resources" => %{"coin" => 5}}
          }
        ], []}}
    ]

    for {name, fronts, events, expected} <- cases do
      {:ok, result} = WorldSim.tick(%{fronts: fronts, events: events})
      assert {result.fronts, result.applied} == expected, name
    end
  end
end
