defmodule AshPaperTrail.FullDiffTest do
  use ExUnit.Case

  alias AshPaperTrail.Test.Posts
  import TestHelper

  setup do
    assert AshPaperTrail.Resource.Info.change_tracking_mode(Posts.FullDiffPost) == :full_diff
    [resource: Posts.FullDiffPost, api: Posts.Api, version_resource: Posts.FullDiffPost.Version]
  end

  describe "simple changes" do
    test "create a new resource", ctx do
      ctx.resource.create!(%{subject: "subject", body: "body", lucky_numbers: [7, 11]})

      assert %{
               subject: %{to: "subject"},
               body: %{to: "body"},
               author: %{to: nil},
               published: %{to: false},
               secret: %{to: nil},
               tags: %{to: nil},
               seo_map: %{to: nil},
               views: %{to: 0},
               lucky_numbers: %{to: [%{index: %{to: 0}, added: 7}, %{index: %{to: 1}, added: 11}]}
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update a resource", ctx do
      ctx.resource.create!(%{subject: "subject", body: "body"})
      |> ctx.resource.update!(%{
        subject: "new subject",
        views: 1,
        lucky_numbers: [7],
        seo_map: %{keywords: ["ash"]}
      })

      assert %{
               subject: %{to: "new subject", from: "subject"},
               body: %{unchanged: "body"},
               author: %{unchanged: nil},
               published: %{unchanged: false},
               secret: %{unchanged: nil},
               tags: %{unchanged: nil},
               seo_map: %{to: %{keywords: ["ash"]}, from: nil},
               source: %{unchanged: nil},
               views: %{from: 0, to: 1},
               lucky_numbers: %{from: nil, to: [%{index: %{to: 0}, added: 7}]}
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "destroy a resource", ctx do
      ctx.resource.create!(%{
        subject: "subject",
        body: "body",
        views: 1,
        lucky_numbers: [7],
        seo_map: %{keywords: ["ash"]}
      })
      |> ctx.resource.destroy!()

      assert %{
               subject: %{unchanged: "subject"},
               body: %{unchanged: "body"},
               author: %{unchanged: nil},
               published: %{unchanged: false},
               secret: %{unchanged: nil},
               tags: %{unchanged: nil},
               seo_map: %{unchanged: %{keywords: ["ash"]}},
               source: %{unchanged: nil},
               views: %{unchanged: 1},
               lucky_numbers: %{unchanged: [%{index: %{unchanged: 0}, unchanged: 7}]}
             } = last_version_changes(ctx.api, ctx.version_resource)
    end
  end

  describe "tracking an embedded resource" do
    test "create with embedded resource", ctx do
      ctx.resource.create!(%{
        author: %{first_name: "Bob"}
      })

      assert %{
               author: %{
                 created: %{
                   first_name: %{to: "Bob"},
                   last_name: %{to: nil},
                   autogenerated_id: %{to: _id}
                 }
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "create an embedded resource", ctx do
      ctx.resource.create!()
      |> ctx.resource.update!(%{author: %{first_name: "Bob"}})

      assert %{
               author: %{
                 created: %{
                   first_name: %{to: "Bob"},
                   last_name: %{to: nil},
                   autogenerated_id: %{to: _id}
                 },
                 from: nil
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update an embedded resource", ctx do
      ctx.resource.create!(%{
        author: %{first_name: "Bob"}
      })
      |> ctx.resource.update!(%{
        author: %{first_name: "Bob", last_name: "Jones"}
      })

      assert %{
               author: %{
                 updated: %{
                   first_name: %{unchanged: "Bob"},
                   last_name: %{from: nil, to: "Jones"},
                   autogenerated_id: %{unchanged: _id}
                 }
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update a resource without updating the embedded resource", ctx do
      ctx.resource.create!(%{
        author: %{first_name: "Bob"}
      })
      |> ctx.resource.update!(%{subject: "new subject"})

      assert %{
               subject: %{to: "new subject"},
               author: %{
                 unchanged: %{
                   first_name: %{unchanged: "Bob"},
                   last_name: %{unchanged: nil}
                 }
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "remove an embedded resource and map", ctx do
      ctx.resource.create!(%{
        author: %{first_name: "Bob"}
      })
      |> ctx.resource.update!(%{author: nil})

      assert %{
               author: %{
                 destroyed: %{
                   first_name: %{from: "Bob"},
                   last_name: %{from: nil},
                   autogenerated_id: %{from: _id}
                 },
                 to: nil
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "destroy with an embedded resource and map", ctx do
      # Destroy is just an update (possibly archived), so the embedded resource
      # is still considered unchanged.

      ctx.resource.create!(%{
        author: %{first_name: "Bob"}
      })
      |> ctx.resource.destroy!()

      assert %{
               author: %{
                 unchanged: %{
                   autogenerated_id: %{unchanged: _auto_id},
                   first_name: %{unchanged: "Bob"},
                   last_name: %{unchanged: nil}
                 }
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end
  end

  describe "change tracking of a union attribute" do
    test "update resource by creating with a union", ctx do
      ctx.resource.create!(%{
        moderator_reaction: 100
      })

      assert %{
               moderator_reaction: %{to: %{type: "score", value: 100}}
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by updating a union", ctx do
      res =
        ctx.resource.create!(%{
          moderator_reaction: 100
        })

      ctx.resource.update!(res, %{
        moderator_reaction: "like"
      })

      assert %{
               moderator_reaction: %{
                 from: %{type: "score", value: 100},
                 to: %{type: "comment", value: "like"}
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource leaving union unchanged", ctx do
      ctx.resource.create!(%{
        moderator_reaction: 100
      })
      |> ctx.resource.update!(%{
        subject: "new subject",
        moderator_reaction: 100
      })

      assert %{
               moderator_reaction: %{
                 unchanged: %{type: "score", value: 100}
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource without union unchanged", ctx do
      res =
        ctx.resource.create!(%{
          moderator_reaction: 100
        })

      ctx.resource.update!(res, %{
        subject: "new subject"
      })

      assert %{
               moderator_reaction: %{
                 unchanged: %{type: "score", value: 100}
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "create resource by creating with a union embedded resource", ctx do
      ctx.resource.create!(%{
        source: %{type: "book", name: "The Book", page: 1}
      })

      assert %{
               source: %{
                 to: %{
                   type: "book",
                   created: %{
                     type: %{to: "book"},
                     name: %{to: "The Book"},
                     page: %{to: 1},
                     id: %{to: _id}
                   }
                 }
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by creating with a union embedded resource", ctx do
      res =
        ctx.resource.create!(%{
          source: nil
        })

      ctx.resource.update!(res, %{
        source: %{type: "book", name: "The Book", page: 1}
      })

      assert %{
               source: %{
                 from: nil,
                 to: %{
                   type: "book",
                   created: %{
                     type: %{to: "book"},
                     name: %{to: "The Book"},
                     page: %{to: 1},
                     id: %{to: _id}
                   }
                 }
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by updating a union embedded resource and leaving unchanged", ctx do
      res =
        ctx.resource.create!(%{
          source: %{type: "book", name: "The Book", page: 1}
        })

      book_id = res.source.value.id

      ctx.resource.update!(res, %{subject: "new subject"})

      assert %{
               source: %{
                 unchanged: %{
                   type: "book",
                   value: %{
                     type: %{unchanged: "book"},
                     name: %{unchanged: "The Book"},
                     page: %{unchanged: 1},
                     id: %{unchanged: ^book_id}
                   }
                 }
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by updating a union embedded resource", ctx do
      res =
        ctx.resource.create!(%{
          source: %{type: "book", name: "The Book", page: 1}
        })

      book_id = res.source.value.id

      ctx.resource.update!(res, %{
        source: %{type: "book", name: "The Other Book", page: 12, id: book_id}
      })

      assert %{
               source: %{
                 updated: %{
                   type: "book",
                   value: %{
                     type: %{unchanged: "book"},
                     name: %{to: "The Other Book", from: "The Book"},
                     page: %{to: 12, from: 1},
                     id: %{unchanged: ^book_id}
                   }
                 }
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by updating a union embedded resource and changing embedded type",
         ctx do
      res =
        ctx.resource.create!(%{
          source: %{type: "book", name: "The Book", page: 1}
        })

      ctx.resource.update!(res, %{
        source: %{type: "blog", name: "The Blog", url: "https://www.myblog.com"}
      })

      assert %{
               source: %{
                 from: %{
                   type: "book",
                   destroyed: %{
                     type: %{from: "book"},
                     name: %{from: "The Book"},
                     page: %{from: 1}
                   }
                 },
                 to: %{
                   type: "blog",
                   created: %{
                     type: %{to: "blog"},
                     name: %{to: "The Blog"},
                     url: %{to: "https://www.myblog.com"}
                   }
                 }
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by updating a union embedded resource and changing to non-embedded type",
         ctx do
      ctx.resource.create!(%{
        subject: "subject",
        body: "body",
        source: %{type: "book", name: "The Book", page: 1}
      })
      |> ctx.resource.update!(%{
        source: "https://www.just-a-link.com"
      })

      assert %{
               source: %{
                 from: %{
                   type: "book",
                   destroyed: %{
                     type: %{from: "book"},
                     name: %{from: "The Book"},
                     page: %{from: 1}
                   }
                 },
                 to: %{type: "link", value: "https://www.just-a-link.com"}
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by updating a union embedded resource and changing from non-embedded type",
         ctx do
      res =
        ctx.resource.create!(%{
          subject: "subject",
          body: "body",
          source: "https://www.just-a-link.com"
        })

      ctx.resource.update!(res, %{
        source: %{type: "book", name: "The Book", page: 1}
      })

      assert %{
               source: %{
                 to: %{
                   type: "book",
                   created: %{
                     type: %{to: "book"},
                     name: %{to: "The Book"},
                     page: %{to: 1}
                   }
                 },
                 from: %{type: "link", value: "https://www.just-a-link.com"}
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by updating a union embedded resource and changing from non-embedded type to non-embedded type",
         ctx do
      ctx.resource.create!(%{
        subject: "subject",
        body: "body",
        source: "https://www.just-a-link.com"
      })
      |> ctx.resource.update!(%{
        source: "https://www.just-another-link.com"
      })

      assert %{
               source: %{
                 from: %{type: "link", value: "https://www.just-a-link.com"},
                 to: %{type: "link", value: "https://www.just-another-link.com"}
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end
  end

  describe "tracking changes an array of embedded resources" do
    test "create a new resource with an array of embedded resources", ctx do
      ctx.resource.create!(%{
        tags: [%{tag: "Ash"}, %{tag: "Phoenix"}]
      })

      assert %{
               tags: %{
                 to: [
                   %{created: %{tag: %{to: "Ash"}, id: %{to: _id1}}, index: %{to: 0}},
                   %{created: %{tag: %{to: "Phoenix"}, id: %{to: _id2}}, index: %{to: 1}}
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update an array of embedded resources", ctx do
      res =
        ctx.resource.create!(%{
          tags: [%{tag: "Ash"}, %{tag: "Phoenix"}]
        })

      %{tags: [%{id: ash_id}, %{id: phx_id}]} = res

      ctx.resource.update!(res, %{
        tags: [%{tag: "Ash", id: ash_id}, %{tag: "Nerves"}, %{tag: "Phx", id: phx_id}]
      })

      assert %{
               tags: %{
                 to: [
                   %{
                     unchanged: %{tag: %{unchanged: "Ash"}, id: %{unchanged: ^ash_id}},
                     index: %{unchanged: 0}
                   },
                   %{created: %{tag: %{to: "Nerves"}, id: %{to: _nerves_id}}, index: %{to: 1}},
                   %{
                     updated: %{tag: %{to: "Phx"}, id: %{unchanged: ^phx_id}},
                     index: %{to: 2, from: 1}
                   }
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update an array with no changes", ctx do
      res =
        ctx.resource.create!(%{
          tags: [%{tag: "Ash"}, %{tag: "Phoenix"}]
        })

      %{tags: [%{id: ash_id}, %{id: phx_id}]} = res

      ctx.resource.update!(res, %{
        tags: [%{tag: "Ash", id: ash_id}, %{tag: "Phoenix", id: phx_id}]
      })

      assert %{
               tags: %{
                 unchanged: [
                   %{
                     unchanged: %{tag: %{unchanged: "Ash"}, id: %{unchanged: ^ash_id}},
                     index: %{unchanged: 0}
                   },
                   %{
                     unchanged: %{tag: %{unchanged: "Phoenix"}, id: %{unchanged: ^phx_id}},
                     index: %{unchanged: 1}
                   }
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update an array with only moves", ctx do
      res =
        ctx.resource.create!(%{
          tags: [%{tag: "Ash"}, %{tag: "Phoenix"}]
        })

      %{tags: [%{id: ash_id}, %{id: phx_id}]} = res

      ctx.resource.update!(res, %{
        tags: [%{tag: "Phoenix", id: phx_id}, %{tag: "Ash", id: ash_id}]
      })

      assert %{
               tags: %{
                 to: [
                   %{
                     unchanged: %{tag: %{unchanged: "Phoenix"}, id: %{unchanged: ^phx_id}},
                     index: %{from: 1, to: 0}
                   },
                   %{
                     unchanged: %{tag: %{unchanged: "Ash"}, id: %{unchanged: ^ash_id}},
                     index: %{from: 0, to: 1}
                   }
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by adding to an empty array of embedded resourcces", ctx do
      res =
        ctx.resource.create!(%{
          tags: []
        })

      ctx.resource.update!(res, %{
        tags: [%{tag: "Ash"}]
      })

      assert %{
               tags: %{
                 to: [
                   %{created: %{tag: %{to: "Ash"}, id: %{to: _ash_id}}, index: %{to: 0}}
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by removing from an array of embedded resources", ctx do
      ctx.resource.create!(%{
        tags: [%{tag: "Ash"}],
        lucky_numbers: [7]
      })
      |> ctx.resource.update!(%{
        tags: []
      })

      assert %{
               tags: %{
                 to: [
                   %{destroyed: %{tag: %{from: "Ash"}, id: %{from: _ash_id}}, index: %{from: 0}}
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update an array of embedded resources to nil", ctx do
      res =
        ctx.resource.create!(%{
          tags: [%{tag: "Ash"}]
        })

      ctx.resource.update!(res, %{
        tags: nil
      })

      assert %{
               tags: %{
                 to: nil,
                 from: [
                   %{destroyed: %{tag: %{from: "Ash"}, id: %{from: _ash_id}}, index: %{from: 0}}
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end
  end

  describe "change tracking an array of union attributes" do
    test "update resource by creating with an array of unions", ctx do
      ctx.resource.create!(%{
        reactions: [2, "like"]
      })

      assert %{
               reactions: %{
                 to: [
                   %{to: %{type: "score", value: 2}, index: %{to: 0}},
                   %{to: %{type: "comment", value: "like"}, index: %{to: 1}}
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by updating an array of unions", ctx do
      res =
        ctx.resource.create!(%{
          reactions: [2, "like"]
        })

      ctx.resource.update!(res, %{
        reactions: ["excellent", "like", 3]
      })

      assert %{
               reactions: %{
                 to: [
                   # 2 was removed from index 0
                   %{from: %{type: "score", value: 2}, index: %{from: 0}},

                   # excellent was added at index 0
                   %{to: %{type: "comment", value: "excellent"}, index: %{to: 0}},

                   # like was unchanged at index 1
                   %{unchanged: %{type: "comment", value: "like"}, index: %{unchanged: 1}},

                   # 3 was added at index 2
                   %{to: %{type: "score", value: 3}, index: %{to: 2}}
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by removing from an array of unions", ctx do
      res =
        ctx.resource.create!(%{
          reactions: [2, "like"]
        })

      ctx.resource.update!(res, %{
        reactions: [2]
      })

      assert %{
               reactions: %{
                 to: [
                   %{unchanged: %{type: "score", value: 2}, index: %{unchanged: 0}},
                   %{from: %{type: "comment", value: "like"}, index: %{from: 1}}
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "create resource with an array of union embedded resources", ctx do
      ctx.resource.create!(%{
        subject: "subject",
        body: "body",
        references: [
          %{type: "book", name: "The Book", page: 1},
          %{type: "blog", name: "The Blog", url: "https://www.myblog.com"},
          "https://www.just-a-link.com"
        ]
      })

      assert %{
               references: %{
                 to: [
                   %{
                     to: %{
                       type: "book",
                       created: %{name: %{to: "The Book"}, page: %{to: 1}, type: %{to: "book"}}
                     },
                     index: %{to: 0}
                   },
                   %{
                     to: %{
                       type: "blog",
                       created: %{
                         type: %{to: "blog"},
                         name: %{to: "The Blog"},
                         url: %{to: "https://www.myblog.com"}
                       }
                     },
                     index: %{to: 1}
                   },
                   %{
                     to: %{type: "link", value: "https://www.just-a-link.com"},
                     index: %{to: 2}
                   }
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by updating union embedded resource in an array", ctx do
      res =
        ctx.resource.create!(%{
          subject: "subject",
          body: "body",
          references: [
            %{type: "book", name: "The Book", page: 1},
            %{type: "blog", name: "The Blog", url: "https://www.myblog.com"},
            "https://www.just-a-link.com"
          ]
        })

      %{references: [%{value: %{id: book_id}}, %{value: %{id: blog_id}}, _]} = res

      ctx.resource.update!(res, %{
        references: [
          %{type: "blog", name: "The Blog", id: blog_id, url: "https://www.myblog.com"},
          "https://www.just-a-link.com",
          %{type: "book", name: "The New Book", page: 1, id: book_id}
        ]
      })

      assert %{
               references: %{
                 to: [
                   %{
                     unchanged: %{
                       type: "blog",
                       value: %{
                         type: %{unchanged: "blog"},
                         name: %{unchanged: "The Blog"},
                         url: %{unchanged: "https://www.myblog.com"}
                       }
                     },
                     index: %{from: 1, to: 0}
                   },
                   %{
                     unchanged: %{type: "link", value: "https://www.just-a-link.com"},
                     index: %{from: 2, to: 1}
                   },
                   %{
                     updated: %{
                       type: "book",
                       value: %{
                         name: %{to: "The New Book"},
                         page: %{unchanged: 1},
                         type: %{unchanged: "book"}
                       }
                     },
                     index: %{from: 0, to: 2}
                   }
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by destroying with a union resource to an embedded array", ctx do
      res =
        ctx.resource.create!(%{
          subject: "subject",
          body: "body",
          references: [
            %{type: "book", name: "The Book", page: 1},
            %{type: "blog", name: "The Blog", url: "https://www.myblog.com"},
            "https://www.just-a-link.com"
          ]
        })

      ctx.resource.update!(res, %{
        references: []
      })

      assert %{
               references: %{
                 to: [
                   %{
                     index: %{from: 0},
                     from: %{
                       type: "book",
                       destroyed: %{
                         id: %{from: _},
                         name: %{from: "The Book"},
                         type: %{from: "book"},
                         page: %{from: 1}
                       }
                     }
                   },
                   %{
                     index: %{from: 1},
                     from: %{
                       type: "blog",
                       destroyed: %{
                         id: %{from: _},
                         name: %{from: "The Blog"},
                         type: %{from: "blog"},
                         url: %{from: "https://www.myblog.com"}
                       }
                     }
                   },
                   %{
                     index: %{from: 2},
                     from: %{type: "link", value: "https://www.just-a-link.com"}
                   }
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "update resource by reordering with a union resource in an embedded array", ctx do
      res =
        ctx.resource.create!(%{
          subject: "subject",
          body: "body",
          references: [
            %{type: "book", name: "The Book", page: 1},
            %{type: "blog", name: "The Blog", url: "https://www.myblog.com"},
            "https://www.just-a-link.com"
          ]
        })

      [%{type: :book, value: %{id: book_id}}, %{type: :blog, value: %{id: blog_id}}, _link] =
        res.references

      ctx.resource.update!(res, %{
        references: [
          "https://www.just-a-link.com",
          %{type: "book", name: "The Book", page: 1, id: book_id},
          %{type: "blog", name: "The Blog", url: "https://www.myblog.com", id: blog_id}
        ]
      })

      assert %{
               references: %{
                 to: [
                   %{
                     index: %{to: 0, from: 2},
                     unchanged: %{type: "link", value: "https://www.just-a-link.com"}
                   },
                   %{
                     index: %{to: 1, from: 0},
                     unchanged: %{
                       type: "book",
                       value: %{
                         id: %{unchanged: ^book_id},
                         name: %{unchanged: "The Book"},
                         type: %{unchanged: "book"},
                         page: %{unchanged: 1}
                       }
                     }
                   },
                   %{
                     index: %{to: 2, from: 1},
                     unchanged: %{
                       type: "blog",
                       value: %{
                         id: %{unchanged: ^blog_id},
                         name: %{unchanged: "The Blog"},
                         type: %{unchanged: "blog"},
                         url: %{unchanged: "https://www.myblog.com"}
                       }
                     }
                   }
                 ]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end
  end

  describe "change tracking a composite of simple types" do
    test "add simple item to a composite array", ctx do
      res = ctx.resource.create!(%{lucky_numbers: [2]})

      assert %{lucky_numbers: %{to: [%{added: 2, index: %{to: 0}}]}} =
               last_version_changes(ctx.api, ctx.version_resource)

      ctx.resource.update!(res, %{lucky_numbers: [2, 3]})

      assert %{
               lucky_numbers: %{
                 to: [%{unchanged: 2, index: %{unchanged: 0}}, %{index: %{to: 1}, added: 3}]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "remove simple item to a composite array", ctx do
      res = ctx.resource.create!(%{lucky_numbers: [2, 3]})

      ctx.resource.update!(res, %{lucky_numbers: [2]})

      assert %{
               lucky_numbers: %{
                 to: [%{index: %{unchanged: 0}, unchanged: 2}, %{index: %{to: 1}, removed: 3}]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end

    test "move simple items in a composite array", ctx do
      res = ctx.resource.create!(%{lucky_numbers: [2, 3]})

      ctx.resource.update!(res, %{lucky_numbers: [3, 2]})

      assert %{
               lucky_numbers: %{
                 to: [%{index: %{from: 1, to: 0}, unchanged: 3}, %{index: %{to: 1, from: 0}, unchanged: 2}]
               }
             } = last_version_changes(ctx.api, ctx.version_resource)
    end
  end
end
